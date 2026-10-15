"""Prints a presigned S3 POST (url and form fields) as JSON.

The POST allows uploading any number of files under the prefix, each stored as <prefix><file name>.
S3's ${filename} placeholder is printed as __FILENAME__, since Terraform would treat ${...} as interpolation.

Usage: presign_post.py <bucket> <prefix> [expires_in_seconds]
"""

import json
import sys

import boto3
from botocore.config import Config

MAX_FILE_SIZE = 1024 * 1024


def main():
    bucket, prefix = sys.argv[1], sys.argv[2]
    expires_in = int(sys.argv[3]) if len(sys.argv) > 3 else 3600

    location = boto3.client("s3", region_name="us-east-1").get_bucket_location(Bucket=bucket)
    region = location["LocationConstraint"] or "us-east-1"
    client = boto3.client(
        "s3",
        region_name=region,
        endpoint_url=f"https://s3.{region}.amazonaws.com",
        config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
    )
    post = client.generate_presigned_post(
        Bucket=bucket,
        Key=prefix + "${filename}",
        Conditions=[["content-length-range", 1, MAX_FILE_SIZE]],
        ExpiresIn=expires_in,
    )
    post["fields"]["key"] = post["fields"]["key"].replace("${filename}", "__FILENAME__")
    print(json.dumps(post))


if __name__ == "__main__":
    main()
