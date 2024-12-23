#!/bin/bash

email_account="heyheyooo"
private_key=~/mykey.asc
key_passphrase="password"

mail_script=mail.py
email_download=/tmp/encrypted_emails
email_decrypted=/tmp/decrypted_emails
completed_dir=/tmp/completed

deliver_docker_dir=/tmp/docker_images_to_send


mkdir -p "$email_download"
mkdir -p "$email_decrypted"
mkdir -p "$completed_dir"
mkdir -p "$deliver_docker_dir"

# add private key to keyring
echo "$key_passphrase" | gpg -q --batch --passphrase-fd 0 --import "$private_key"

# download new emails
python3 "$mail_script" --email_account "$email_account" --output_directory "$email_download"

# decrypt and remove any new emails
for i in $(find "$email_download" -type f)
do
    echo "$key_passphrase" | gpg --batch --decrypt --output "$email_decrypted/$(basename $i).txt" "$i" && rm "$i"
done

# process decrypted emails containing docker pull commands
for i in $(find "$email_decrypted" -type f)
do
    success=""
    while read -r line
    do
        ./docker_fetch.sh "$(echo $line | sed 's/docker[[:space:]]\{1,\}pull[[:space:]]\{1,\}//g')" "$deliver_docker_dir"
        success="yep"
    done < <(grep "docker pull" "$i")

    if [[ ! -z $success ]]
    then
        mv "$i" "$completed_dir"
    fi
done


