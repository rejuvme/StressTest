#!/usr/bin/env python3
import argparse
import datetime as dt
import email
import imaplib
import json
import re
import sys
import time
from email.header import decode_header, make_header
from email.utils import parsedate_to_datetime

CODE_RE = re.compile(r'(?<!\d)(\d{6})(?!\d)')


def decode_text(value: str | None) -> str:
    if not value:
        return ''
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def extract_text(msg: email.message.Message) -> str:
    parts: list[str] = []
    if msg.is_multipart():
        for part in msg.walk():
            content_type = (part.get_content_type() or '').lower()
            content_disp = (part.get('Content-Disposition') or '').lower()
            if 'attachment' in content_disp:
                continue
            if content_type in ('text/plain', 'text/html'):
                payload = part.get_payload(decode=True)
                charset = part.get_content_charset() or 'utf-8'
                if payload is None:
                    continue
                try:
                    parts.append(payload.decode(charset, errors='replace'))
                except Exception:
                    parts.append(payload.decode('utf-8', errors='replace'))
    else:
        payload = msg.get_payload(decode=True)
        charset = msg.get_content_charset() or 'utf-8'
        if payload is not None:
            try:
                parts.append(payload.decode(charset, errors='replace'))
            except Exception:
                parts.append(payload.decode('utf-8', errors='replace'))
    return '\n'.join(parts)


def normalize_dt(value: dt.datetime | None) -> dt.datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc)


def search_for_code(args: argparse.Namespace) -> dict:
    deadline = time.time() + args.timeout_seconds
    issued_after = dt.datetime.fromtimestamp(args.issued_after_epoch, tz=dt.timezone.utc)

    while time.time() < deadline:
        with imaplib.IMAP4_SSL('imap.gmail.com', 993) as client:
            client.login(args.gmail_user, args.gmail_app_password)
            client.select('INBOX')
            status, data = client.search(None, 'ALL')
            if status != 'OK':
                raise RuntimeError('Failed to search Gmail inbox')

            message_ids = data[0].split()
            for message_id in reversed(message_ids[-50:]):
                fetch_status, fetched = client.fetch(message_id, '(RFC822)')
                if fetch_status != 'OK':
                    continue
                raw_bytes = None
                for item in fetched:
                    if isinstance(item, tuple) and len(item) >= 2:
                        raw_bytes = item[1]
                        break
                if not raw_bytes:
                    continue
                msg = email.message_from_bytes(raw_bytes)
                subject = decode_text(msg.get('Subject'))
                from_value = decode_text(msg.get('From'))
                to_value = decode_text(msg.get('To'))
                date_value = normalize_dt(parsedate_to_datetime(msg.get('Date'))) if msg.get('Date') else None

                if date_value and date_value < issued_after:
                    continue
                if args.from_filter and args.from_filter.lower() not in from_value.lower():
                    continue
                if args.subject_filter and args.subject_filter.lower() not in subject.lower():
                    continue
                if args.to_filter and args.to_filter.lower() not in to_value.lower():
                    body = extract_text(msg)
                    if args.to_filter.lower() not in body.lower():
                        continue
                else:
                    body = extract_text(msg)

                haystack = '\n'.join([subject, body])
                match = CODE_RE.search(haystack)
                if not match:
                    continue

                return {
                    'code': match.group(1),
                    'subject': subject,
                    'from': from_value,
                    'to': to_value,
                    'date': date_value.isoformat() if date_value else '',
                }

        time.sleep(args.poll_interval_seconds)

    raise TimeoutError('Timed out waiting for OTP email in Gmail inbox')


def main() -> int:
    parser = argparse.ArgumentParser(description='Poll Gmail for the newest RejuvMe OTP email and extract its 6-digit code.')
    parser.add_argument('--gmail-user', required=True)
    parser.add_argument('--gmail-app-password', required=True)
    parser.add_argument('--to-filter', default='')
    parser.add_argument('--from-filter', default='')
    parser.add_argument('--subject-filter', default='')
    parser.add_argument('--timeout-seconds', type=int, default=180)
    parser.add_argument('--poll-interval-seconds', type=int, default=5)
    parser.add_argument('--issued-after-epoch', type=float, required=True)
    args = parser.parse_args()

    try:
        result = search_for_code(args)
    except Exception as exc:
        print(json.dumps({'ok': False, 'error': str(exc)}))
        return 1

    print(json.dumps({'ok': True, **result}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
