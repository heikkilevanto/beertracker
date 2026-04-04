#!/bin/bash
# A little cron job script to trigger reloading of beer board

curl -s -X POST http://127.0.0.1/beertracker/ -d "o=updateboard&loc=Ølbaren"
curl -s -X POST http://127.0.0.1/beertracker/ -d "o=updateboard&loc=Taphouse"
curl -s -X POST http://127.0.0.1/beertracker/ -d "o=updateboard&loc=Brus"

