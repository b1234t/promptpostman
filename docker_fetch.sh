#!/bin/bash

# Temp file to store results
TEMP_FILE=$(mktemp)
> "$TEMP_FILE"  # Clear the file if it exists

image=$(echo "$1" | awk -F':' '{print $1}')
requested_tag=$(echo "$1" | awk -F':' '{print $2}')

output_dir="$2"

# pull requested image, and capture the digest
digest=$(docker pull $1 | grep Digest | grep -o 'sha256.*$')

if [[ -z $digest ]]
then
    echo "Could not find docker image digest... does this image actually exist?? $1"
    exit 1
fi

# Base API endpoint
API_ENDPOINT="https://hub.docker.com/v2/repositories/$image/tags"
PAGE=1
PAGE_SIZE=100 # docker hub typically only returns max 100 no matter how big the page


# check to see if we need to add library prefix
curl -L -s -f "$API_ENDPOINT"
if [[ $? -ne 0 ]]
then
    API_ENDPOINT="https://hub.docker.com/v2/repositories/library/$image/tags"
fi


while true; do
  # Fetch the current page (fail if we get an error like 404 when we run out of pages)
  RESPONSE=$(curl -L -s -f "${API_ENDPOINT}?page_size=${PAGE_SIZE}&page=${PAGE}")

  if [[ $? -ne 0 ]]
  then
    break
  fi
  
  # Check if the response contains results
  RESULTS=$(echo "$RESPONSE" | jq '.results[] | "\(.name) \(.digest)"' 2>/dev/null)
  
  if [ -z "$RESULTS" ]; then
    break
  fi
  
  # Append results to the temp file
  echo "$RESULTS" >> "$TEMP_FILE"
  
  # Increment the page counter
  PAGE=$((PAGE + 1))
done

tag_list="$1"
for tag in $(grep $digest $TEMP_FILE | sed 's/"//g' | awk '{print $1}')
do
    docker pull $image:$tag
    tag_list="${tag_list} $image:$tag"
done

# now save out an image with all of our accumulated tags
name="__docker_container__$(basename $image)"_"$RANDOM.tar.gz"
echo "SAVING IMAGE FILE: $name  -- including tags: $tag_list"
docker save $tag_list | gzip > "$output_dir/.$name"
mv "$output_dir/.$name" "$output_dir/$name"

# now clean up docker
# get image id for our digest
image_id=$(docker images --digests | grep $digest | awk '{print $4}' | head -1)
# force remove of our image id in case there are multiple tags for it
docker rmi -f $image_id

rm "$TEMP_FILE"
