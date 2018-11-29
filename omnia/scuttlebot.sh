#!/usr/bin/env bash

#get id of scuttlebot peer
getFeedId () {
	local _id
	_id=$("$HOME"/scuttlebot/bin.js whoami | jq '.id')
	sed -e 's/^"//' -e 's/"$//' <<<"$_id"
}

pullMessages () {
    #this would is used for pulling all messages from all feeds with in-bounds timestamp
    #returns an array of objects containg only relevant info
    #breaks up that array into nested subarrays by feed
    local _type=$1
    local _after=$2
    local _limit=$3
    #TODO pass args into jq
    "$HOME"/scuttlebot/bin.js logt --type "$_type" | jq -S 'select(.value.content.time >= 1536082440) | {author: .value.author, time: .value.timestamp, price: .value.content.median}' | jq -s 'group_by(.author)'
}

#pull latest message from feed
pullLatestFeedMsg () {
	local _feed="$1"
    "$HOME"/scuttlebot/bin.js getLatest "$_feed" | jq -S '{author: .value.author, time: .value.timestamp, msgID: .key, previous: .value.previous, type: .value.content.type, price: .value.content.median}' 
}

#pull previous message
pullPreviousFeedMsg () {
    #trim quotes from prev key
    local _prev
    _prev=$(sed -e 's/^"//' -e 's/"$//' <<<"$@")
    "$HOME"/scuttlebot/bin.js get "$_prev" | jq -S '{author: .author, time: .timestamp, previous: .previous, type: .content.type, price: .content.median}'
}

#pull latest message of type _ from feed
pullLatestFeedMsgOfType () {
	local _feed=$1
	local _asset=$2
    local _counter=0
    local _msg
    #get latest message from feed
    _msg=$( pullLatestFeedMsg "$_feed" )
    verbose "latest message = $_msg"
    #if message does not contain a price, get the previous message until we find one that does
    while (( _counter < 10 )) && [[ $(isAsset "$_asset" "$_msg") == "false" ]]; do
        #clear previous key
        local _key=""
        #get key of previous message
        _key=$( echo "$_msg" | jq '.previous' )
        #clear previous message
        _msg=""
        #stop looking if no more messages
        [[ $_key == "null" ]] && break
        #grab previous message
        _msg=$( pullPreviousFeedMsg "$_key" )
        verbose "previous message = $_msg"
        #increment message counter
        _counter=$(( _counter + 1 ))
    done
	echo "$_msg"
}

#publish price  to scuttlebot
broadcastPriceMsg () {
    local _assetType="$1"
    local _median="$2"
    local _medianHex="$3"
    local _time="$4"
    local _timeHex="$5"
    local _hash="$6"
    local _sig="$7"
    cmd="$HOME/scuttlebot/bin.js publish --type $_assetType --version $OMNIA_VERSION --median $_median --0xmedian $_medianHex --time $_time --0xtime $_timeHex --hash ${_hash:2} --signature ${_sig:2}"
    [[ "${#validSources[@]}" != "${#validPrices[@]}" ]] && error "Error: number of sources doesn't match number of prices" && exit 1
    for index in ${!validSources[*]}; do
        cmd+=" --${validSources[index]} ${validPrices[index]}"
    done
    log "Submitting new price message..."
    verbose "$cmd"
    verbose "$(eval "$cmd")"
}