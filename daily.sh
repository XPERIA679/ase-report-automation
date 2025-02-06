#!/bin/bash

if [[ -f .env ]]; then
    source .env
else
    echo ".env file not found!"
    exit 1
fi

JWT_HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | openssl base64 | tr -d '\n=' | tr '/+' '_-')

NOW=$(date +%s)
EXP=$(($NOW + 3600))
JWT_CLAIM=$(echo -n "{\"iss\":\"$CLIENT_EMAIL\",\"scope\":\"https://www.googleapis.com/auth/spreadsheets.readonly\",\"aud\":\"https://oauth2.googleapis.com/token\",\"exp\":$EXP,\"iat\":$NOW}" | openssl base64 | tr -d '\n=' | tr '/+' '_-')

PRIVATE_KEY_FILE=$(mktemp)
echo -e "$PRIVATE_KEY" > "$PRIVATE_KEY_FILE"

SIGNATURE=$(echo -n "$JWT_HEADER.$JWT_CLAIM" | openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" | openssl base64 | tr -d '\n=' | tr '/+' '_-')

rm "$PRIVATE_KEY_FILE"

JWT="$JWT_HEADER.$JWT_CLAIM.$SIGNATURE"

ACCESS_TOKEN=$(curl -s --request POST \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$JWT" \
    https://oauth2.googleapis.com/token | jq -r .access_token)

fetch_range_data() {
    local RANGE_NAME=$1
    local RANGE=$2
    local DATA=""

    RESPONSE=$(curl -s --request GET \
        "https://sheets.googleapis.com/v4/spreadsheets/$SHEET_ID/values/$RANGE?access_token=$ACCESS_TOKEN")

    if [[ $(echo "$RESPONSE" | jq -r .error) != "null" ]]; then
        echo "Error fetching $RANGE_NAME data: $RESPONSE"
        exit 1
    fi

    VALUES=$(echo "$RESPONSE" | jq -r .values)

    if [[ "$VALUES" == "null" || -z "$VALUES" ]]; then
        DATA="No values found for $RANGE_NAME."
    else
        DATA=$(echo "$VALUES" | jq -r '.[] | .[]' | sed '/^\s*$/d' | tr '\n' ' ')
    fi
    
    echo "$DATA"
}

print_summary() {
    local RANGE_NAME=$1
    local RANGE=$2

    local SUMMARY=$(fetch_range_data "$RANGE_NAME" "$RANGE")

    echo "Summary for $RANGE_NAME:"
    echo "$SUMMARY"
}

fetch_mention_user() {
    local REPORTER_NAME=$(fetch_range_data "REPORTER" "$RANGE_REPORTER" | xargs)
    local MENTION_USER=""

    case $REPORTER_NAME in
        "Mikco")
            MENTION_USER=$MENTION_MIKCO
            ;;
        "Robin")
            MENTION_USER=$MENTION_ROBIN
            ;;
        "Emman")
            MENTION_USER=$MENTION_EMMAN
            ;;
        "Francis")
            MENTION_USER=$MENTION_FRANCIS
            ;;
        *)
            MENTION_USER="Error: REPORTER_NAME is $REPORTER_NAME"
            ;;
    esac

    echo "$MENTION_USER"
}

FINAL_MESSAGE+=$(print_summary "ROBIN" "$RANGE_ROBIN")
FINAL_MESSAGE+=$(print_summary "EMMAN" "$RANGE_EMMAN")
FINAL_MESSAGE+=$(print_summary "MIKCO" "$RANGE_MIKCO")
FINAL_MESSAGE+=$(print_summary "FRANCIS" "$RANGE_FRANCIS")

TEXT="Summarize the content of $FINAL_MESSAGE. Make sure that the summary is in bullet form and each person has its own summary. Start with the name then newline, then bullet points then newline again for the next person. Dont add any format to the names. Make it few words per report only. Dont over add further details, only important ones. As much as possible, make it 2 bullet forms"

generate_summary() {
  RESPONSE=$(curl -s -H 'Content-Type: application/json' \
    -d '{"contents":[{"parts":[{"text":"'"$TEXT"'"}]}]}' \
    -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$GEMINI_API_KEY")
  echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text'
}

CHATWORK_REMINDER="Good morning! Don't forget to message in Chatwork~"
SUMMARY=$(generate_summary)
MENTION_USER=$(fetch_mention_user)
CC="Reporter: $MENTION_USER"
REPORT=$(echo -e "$CHATWORK_REMINDER\n\n$SUMMARY\n\n$CC")

JSON_PAYLOAD=$(jq -n --arg text "$REPORT" '{text: $text}')
echo "$JSON_PAYLOAD"
RESPONSE=$(curl -s -X POST "$DAILY_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

echo "Notification sent to bot: $RESPONSE"
