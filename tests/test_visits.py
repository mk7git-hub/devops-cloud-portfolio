import json

from backend import visits


class FakeDynamo:
    def __init__(self):
        self.n = 0

    def update_item(self, **kw):
        assert kw["UpdateExpression"] == "ADD visits :one"
        self.n += 1
        return {"Attributes": {"visits": {"N": str(self.n)}}}

    def get_item(self, **kw):
        return {"Item": {"visits": {"N": str(self.n)}}} if self.n else {}


def call(method, ddb):
    r = visits.handler({"requestContext": {"http": {"method": method}}}, None, ddb=ddb)
    return r["statusCode"], json.loads(r["body"]), r["headers"]


def test_post_increments_atomically():
    ddb = FakeDynamo()
    assert call("POST", ddb)[1] == {"visits": 1}
    assert call("POST", ddb)[1] == {"visits": 2}


def test_get_reads_without_incrementing():
    ddb = FakeDynamo()
    assert call("GET", ddb)[1] == {"visits": 0}
    call("POST", ddb)
    assert call("GET", ddb)[1] == {"visits": 1}
    assert ddb.n == 1


def test_other_methods_rejected():
    assert call("DELETE", FakeDynamo())[0] == 405


def test_responses_are_never_cached():
    assert call("GET", FakeDynamo())[2]["Cache-Control"] == "no-store"
