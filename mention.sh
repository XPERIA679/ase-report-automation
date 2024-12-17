#!/bin/bash

# if [[ -f .env ]]; then
#     source .env
# else
#     echo ".env file not found!"
#     exit 1
# fi

LOWEST_NAME=""
LOWEST_COUNT=999999  

while IFS=" - " read -r name count; do
    count=$(echo "$count" | tr -d '[:space:]') 
    if [[ "$count" =~ ^[0-9]+$ && $count -lt $LOWEST_COUNT ]]; then  
        LOWEST_NAME=$name
        LOWEST_COUNT=$count
    fi
done < tally.txt

case $LOWEST_NAME in
    "mikco")
        MENTION_USER=$MENTION_MIKCO
        ;;
    "robin")
        MENTION_USER=$MENTION_ROBIN
        ;;
    "emman")
        MENTION_USER=$MENTION_EMMAN
        ;;
    "shiara")
        MENTION_USER=$MENTION_SHIARA
        ;;
    *)
        echo "Unknown user: $LOWEST_NAME"
        exit 1
        ;;
esac

TEXT="CC: $MENTION_USER"

JSON_PAYLOAD=$(jq -n --arg text "$TEXT" '{text: $text}')

RESPONSE=$(curl -s -X POST "$DAILY_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

echo "Notification sent to bot: $RESPONSE"

if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i "" "s/^$LOWEST_NAME - $LOWEST_COUNT$/$LOWEST_NAME - $((LOWEST_COUNT + 1))/g" tally.txt
else
    sed -i "s/^$LOWEST_NAME - $LOWEST_COUNT$/$LOWEST_NAME - $((LOWEST_COUNT + 1))/g" tally.txt
fi
