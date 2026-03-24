import json
import pickle
import random
from typing import List

from .recommender import Recommender

HISTORY_LIMIT   = 30
LIKE_THRESHOLD  = 0.5


class MyRecommender(Recommender):
    def __init__(self, listen_history_redis, lfm_redis, fallback):
        self.listen_history_redis = listen_history_redis
        self.lfm_redis            = lfm_redis
        self.fallback             = fallback

    def _load_history(self, user: int) -> List[int]:
        """Возвращает список недавно прослушанных track_id."""
        key  = f"user:{user}:listens"
        raws = self.listen_history_redis.lrange(key, 0, HISTORY_LIMIT - 1)
        seen = []
        for raw in raws:
            entry = json.loads(raw.decode() if isinstance(raw, bytes) else raw)
            seen.append(int(entry["track"]))
        return seen

    def _lfm_recommendations(self, user: int) -> List[int]:
        """Персональные рекомендации из LightFM по user_id."""
        data = self.lfm_redis.get(user)
        if data is None:
            return []
        return list(pickle.loads(data))

    def recommend_next(self, user: int, prev_track: int, prev_track_time: float) -> int:
        recs = self._lfm_recommendations(user)

        if not recs:
            return self.fallback.recommend_next(user, prev_track, prev_track_time)

        # Исключаем недавно прослушанные
        seen = set(self._load_history(user))
        candidates = [t for t in recs if t not in seen]

        if not candidates:
            candidates = recs  # все уже слышали — рекомендуем заново

        if prev_track_time < LIKE_THRESHOLD:
            # трек не понравился — случайный из рекомендаций
            return int(random.choice(candidates))
        else:
            # трек понравился — следующий по рейтингу
            return int(candidates[0])