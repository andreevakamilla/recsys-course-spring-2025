import json
import logging
import time
from dataclasses import asdict
from datetime import datetime

from flask import Flask
from flask_redis import Redis
from flask_restful import Resource, Api, abort, reqparse
from gevent.pywsgi import WSGIServer

from botify.data import DataLogger, Datum
from botify.experiment import Experiments, Treatment
from botify.recommenders.random import Random
from botify.recommenders.sticky_artist import StickyArtist
from botify.recommenders.myrecom import MyRecommender
from botify.track import Catalog

root = logging.getLogger()
root.setLevel("INFO")

app = Flask(__name__)
app.config.from_file("config.json", load=json.load)
api = Api(app)

tracks_redis         = Redis(app, config_prefix="REDIS_TRACKS")
artists_redis        = Redis(app, config_prefix="REDIS_ARTIST")
listen_history_redis = Redis(app, config_prefix="REDIS_LISTEN_HISTORY")
lfm_redis            = Redis(app, config_prefix="REDIS_RECOMMENDATIONS_LFM")

data_logger = DataLogger(app)

catalog = Catalog(app).load(app.config["TRACKS_CATALOG"])
catalog.upload_tracks(tracks_redis.connection)
catalog.upload_artists(artists_redis.connection)

catalog.upload_recommendations(
    lfm_redis.connection,
    "RECOMMENDATIONS_LFM_FILE_PATH",
    key_object="user",
    key_recommendations="tracks",
)

random_recommender = Random(tracks_redis.connection)

sticky_artist_recommender = StickyArtist(
    tracks_redis.connection,
    artists_redis.connection,
    catalog,
)

# T1 → MyRecommender (тритмент)
my_recommender = MyRecommender(
    listen_history_redis.connection,
    lfm_redis.connection,
    random_recommender,
)

parser = reqparse.RequestParser()
parser.add_argument("track", type=int,   location="json", required=True)
parser.add_argument("time",  type=float, location="json", required=True)

LISTEN_HISTORY_LIMIT = 30


def persist_listen_history(user: int, track: int, track_time: float):
    key   = f"user:{user}:listens"
    entry = json.dumps({"track": track, "time": track_time})
    listen_history_redis.connection.lpush(key, entry)
    listen_history_redis.connection.ltrim(key, 0, LISTEN_HISTORY_LIMIT - 1)


class Hello(Resource):
    def get(self):
        return {"status": "alive"}


class Track(Resource):
    def get(self, track: int):
        data = tracks_redis.connection.get(track)
        if data is not None:
            return asdict(catalog.from_bytes(data))
        abort(404, description="Track not found")


class NextTrack(Resource):
    def post(self, user: int):
        start = time.time()
        args  = parser.parse_args()

        persist_listen_history(user, args.track, args.time)

        treatment = Experiments.MYREC_VS_STICKY.assign(user)

        if treatment == Treatment.C:
            recommender = sticky_artist_recommender
        elif treatment == Treatment.T1:
            recommender = my_recommender
        else:
            recommender = sticky_artist_recommender

        recommendation = recommender.recommend_next(user, args.track, args.time)

        data_logger.log(
            "next",
            Datum(
                int(datetime.now().timestamp() * 1000),
                user, args.track, args.time,
                time.time() - start,
                recommendation,
            ),
        )
        return {"user": user, "track": recommendation}


class LastTrack(Resource):
    def post(self, user: int):
        start = time.time()
        args  = parser.parse_args()
        data_logger.log(
            "last",
            Datum(
                int(datetime.now().timestamp() * 1000),
                user, args.track, args.time,
                time.time() - start,
            ),
        )
        return {"user": user}


api.add_resource(Hello,     "/")
api.add_resource(Track,     "/track/<int:track>")
api.add_resource(NextTrack, "/next/<int:user>")
api.add_resource(LastTrack, "/last/<int:user>")

app.logger.info("Botify service started")

if __name__ == "__main__":
    http_server = WSGIServer(("", 5001), app)
    http_server.serve_forever()