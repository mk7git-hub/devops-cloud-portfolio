"""Visitor counter: atomically increments one DynamoDB item and returns the new total.

Behind CloudFront /api/visits. POST increments, GET reads. No PII is stored: just a number.
"""
import json
import os

import boto3

TABLE = os.environ.get("TABLE_NAME", "")
KEY = {"id": {"S": "site"}}
_ddb = None


def client():
    global _ddb
    if _ddb is None:
        _ddb = boto3.client("dynamodb")
    return _ddb


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"},
        "body": json.dumps(body),
    }


def handler(event, _context, ddb=None):
    ddb = ddb or client()
    method = (event.get("requestContext", {}).get("http", {}).get("method") or "GET").upper()
    if method == "POST":
        out = ddb.update_item(
            TableName=TABLE,
            Key=KEY,
            UpdateExpression="ADD visits :one",
            ExpressionAttributeValues={":one": {"N": "1"}},
            ReturnValues="UPDATED_NEW",
        )
        return response(200, {"visits": int(out["Attributes"]["visits"]["N"])})
    if method == "GET":
        item = ddb.get_item(TableName=TABLE, Key=KEY).get("Item")
        return response(200, {"visits": int(item["visits"]["N"]) if item else 0})
    return response(405, {"error": "method not allowed"})
