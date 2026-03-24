FROM python:3.7-slim-buster

WORKDIR /app

COPY requirements.txt .

RUN pip install --timeout 120 --retries 5 -r requirements.txt

COPY botify ./botify
COPY data ./data

RUN mkdir -p ./log

ENV PYTHONPATH "${PYTHONPATH}:/app"