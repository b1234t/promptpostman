import argparse
import os
import uuid
from email import policy
from email.parser import BytesParser
from pathlib import Path
from typing import Dict, Any, List

import requests

class GuerrillaMailClient:
    def __init__(self, email_acct: str):
        self.email_acct = None
        self.session_id = None
        self.set_email_user(email_acct)

    def _do_api_request(self, **kwargs) -> Dict[str, Any]:
        url = f'https://api.guerrillamail.com/ajax.php'
        if self.session_id is not None:
            kwargs['sid_token'] = self.session_id

        response = requests.get(url, params=kwargs)

        response.raise_for_status()

        self.session_id = response.json().get("sid_token")

        return response.json()

    def set_email_user(self, email_acct: str) -> None:
        self.email_acct = email_acct
        self._do_api_request(f='set_email_user', email_user=email_acct)

    def get_email_raw(self, email_id: str, **kwargs) -> str:
        url = f'https://www.guerrillamail.com/inbox?show_source={email_id}'

        kwargs['show_source'] = email_id
        kwargs['sid_token'] =  self.session_id

        response = requests.get(url, params=kwargs)

        response.raise_for_status()

        return response.text

    def list_emails(self) -> List[Dict[str, Any]]:
        return self._do_api_request(f='get_email_list', offset='0').get('list')

    def list_email_ids(self) -> List[str]:
        return [i.get("mail_id") for i in self.list_emails()]

    def get_plain_text_body(self, email_id: str) -> str:
        raw_content = self.get_email_raw(email_id)
        msg = BytesParser(policy=policy.default).parsebytes(raw_content.encode("utf-8"))
        body = msg.get_body(preferencelist=('plain', 'html'))
        return body.get_content()

    def del_email(self, email_ids: List[str]) -> None:
        params = {"email_ids[]" : email_ids }
        self._do_api_request(f='del_email', **params)


def main():

    # Create the argument parser
    parser = argparse.ArgumentParser(
        description="Download plain text email bodies from an account and save to an output dir")

    # Add arguments
    parser.add_argument(
        "--email_account",
        type=str,
        help="Email account as a string"
    )
    parser.add_argument(
        "--output_directory",
        type=str,
        help="Output directory path"
    )

    # Parse the arguments
    args = parser.parse_args()

    # Validate the output directory
    out_dir = Path(args.output_directory)
    if not out_dir.is_dir():
        print(f"Error: The provided path '{args.output_directory}' is not a valid directory.")
        exit(1)

    client = GuerrillaMailClient(args.email_account)

    emails = client.list_email_ids()
    for email_id in emails:
        fn = f"{str(uuid.uuid4())}.pgp"
        content = client.get_plain_text_body(email_id)

        if "-----BEGIN PGP MESSAGE-----" not in content:
            continue

        with open(out_dir.joinpath(fn), 'wt') as f:
            f.write(content)
        client.del_email([email_id])

if __name__ == '__main__':
    main()
