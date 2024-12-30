#!/bin/bash

private_key=~/mykey.asc
key_passphrase="password"

mail_script=mail.py
email_download=/tmp/encrypted_emails
email_decrypted=/tmp/decrypted_emails
completed_dir=/tmp/completed_emails

deliver_dir=/tmp/docker_images_to_send

mkdir -p "$email_download"
mkdir -p "$email_decrypted"
mkdir -p "$completed_dir"
mkdir -p "$deliver_dir"

declare -a inboxes=(
"e05f9f92-ab65-44c9-a19e-cff2cdceb69e"
"9d6ea051-bafc-462d-a92d-b456f2f81aa7"
"d80e548b-5935-4650-9005-7841c26f7cfe"
"81f3d3e7-c5a7-42d8-86a6-4e647f02800e"
"79267c8f-86e7-4939-a4bd-fdb110f83b22"
"0a5e7cea-1106-482e-84c7-95d93fea32c8"
"43027d9a-9178-4a0f-8299-e3efdcae6508"
"d783a568-22a4-43d8-83b3-52ab5f8fcc4f"
"648865fc-03a0-4a18-9747-6b847cde4dbe"
)

# add private key to keyring
gpg -q --batch --passphrase "$key_passphrase" --import "$private_key"

# download new emails from all accounts
for email_account in ${inboxes[@]}
do
    python3 "$mail_script" --email_account "$email_account" --output_directory "$email_download"
done

# if there is nothing new we can exit as there is no futher processing necessary
if [[ $(ls "$email_download" | wc -l) -eq 0 ]]
then
    exit 0
fi

log_file=$(mktemp)

echo "$(date "+%Y-%m-%d %H:%M:%S") - Found $(ls "$email_download" | wc -l) new email(s)" >> "$log_file"
find "$email_download" -type f >> "$log_file"

# decrypt and remove any new emails
for i in $(find "$email_download" -type f)
do
    gpg -q --batch --passphrase "$key_passphrase" --pinentry-mode loopback --decrypt --output "$email_decrypted/$(basename $i).txt" "$i" && rm "$i"
done

echo "$(date "+%Y-%m-%d %H:%M:%S") - Decrypted $(ls "$email_decrypted" | wc -l) new email(s)" >> "$log_file"
find "$email_decrypted" -type f >> "$log_file"


# process decrypted emails containing commands
for i in $(find "$email_decrypted" -type f)
do
    # parse the inbox id by retrieving the first part of the fn before the underscore (the email downloader should name the files this way)
    email_inbox=$(echo "$i" | awk -F'_' '{print $1}')
    success=""
    while read -r line
    do
        #trim line
        line=$(echo "$line" | xargs)

        # support docker pull commands
        if echo "$line" | grep -q "docker pull"
        then
            success="yep"
            echo "$(date "+%Y-%m-%d %H:%M:%S") - $email_inbox requested download docker: $line" >> "$log_file"
            ./docker_fetch.sh "$(echo $line | sed 's/docker[[:space:]]\{1,\}pull[[:space:]]\{1,\}//g')" "$deliver_dir" >> "$log_file"
        fi

        # support arbitrary http downloads
        if echo "$line" | grep -q -P "^http"
        then
            success="yep"
            echo "$(date "+%Y-%m-%d %H:%M:%S") - $email_inbox requested download of file: $line" >> "$log_file"
            tmp_dir=$(mktemp)
            curl --no-progress-meter -O --output-dir "$tmp_dir" "$line" >> "$log_file" 2>&1
            downloaded_file_name=$(ls "$tmp_dir")
            mv "$tmp_dir/$downloaded_file_name" "$deliver_dir/.__pp_download__$email_inbox"__"$downloaded_file_name"
            mv "$deliver_dir/.__pp_download__$email_inbox"__"$downloaded_file_name" "$deliver_dir/__pp_download__$email_inbox"__"$downloaded_file_name"
            rm -r "$tmp_dir"
        fi

        # suport helm pull
        if echo "$line" | grep -q "helm pull"
        then
            # TODO: add helm pull support
            # note: we should support things like:
            # > helm pull nginx --repo https://charts.bitnami.com/bitnami
            # > helm pull bitnami/nginx --version 13.2.15
            # we can use --destination to specify an output directory which we may want to do for each pull so we can easily identify the .tgz file that is produced from the command
        fi
        
    done < <(cat "$i")

    if [[ -z $success ]]
    then
        echo "ERROR: NO VALID COMMANDS FOUND - from: $i" >> "$log_file"
    fi

    # archive this file as 'complete'
    mv "$i" "$completed_dir"
done


echo "$(date "+%Y-%m-%d %H:%M:%S") - DONE" >> "$log_file"

# send the log file
mv "$log_file" "$deliver_dir/__promptpostman_log__$(date +%s).log"


