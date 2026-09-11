import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ResponseHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(self.server.status)
        self.end_headers()
        self.wfile.write(self.server.body.encode())

    def log_message(self, *args):
        pass


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        shutil.copytree(ROOT / "scripts", self.work / "scripts")
        for script in (self.work / "scripts").glob("*.sh"):
            script.chmod(0o755)
        kubectl = self.work / "kubectl"
        kubectl.write_text('''#!/usr/bin/env python3
import os, subprocess, sys
args = sys.argv[1:]
if args[:2] == ["get", "solrcloud"]:
    print(os.environ["TEST_CR"])
elif args[:2] == ["config", "current-context"]:
    print("test-context")
elif args[0] == "exec":
    config = sys.stdin.read().replace("http://localhost:8983", os.environ["TEST_URL"])
    sys.exit(subprocess.run(args[args.index("--") + 1:], input=config, text=True).returncode)
else:
    sys.exit(1)
''')
        kubectl.chmod(0o755)
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ResponseHandler)
        self.server.status = 200
        self.server.body = "{}"
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.env = dict(os.environ, PATH=f"{self.work}:{os.environ['PATH']}",
                        TEST_CR='{"spec": {}}',
                        TEST_URL=f"http://127.0.0.1:{self.server.server_port}",
                        SOLR_MCP_URL="")

    def run_script(self, name, *args):
        return subprocess.run([str(self.work / "scripts" / name), "films", "search", *args],
                              env=self.env, text=True, capture_output=True)

    def test_scripts_are_executable(self):
        for script in (ROOT / "scripts").glob("*.sh"):
            with self.subTest(script=script.name):
                self.assertTrue(os.access(script, os.X_OK))

    def test_http_errors_fail(self):
        for status in (401, 404, 500):
            self.server.status = status
            self.server.body = '{"error": {"msg": "failed"}}'
            with self.subTest(status=status):
                result = self.run_script("solr-api.sh", "GET", "admin/collections")
                self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_invalid_cluster_responses_fail(self):
        valid_cluster = {"live_nodes": [], "collections": {}}
        responses = [{"error": {}}, {},
                     {"responseHeader": {"status": 1}, "cluster": valid_cluster},
                     {"responseHeader": {"status": 0}},
                     {"responseHeader": {"status": 0}, "cluster": {}},
                     {"responseHeader": {"status": 0},
                      "cluster": {"live_nodes": {}, "collections": []}}]
        for body in [json.dumps(value) for value in responses] + ["", "not json"]:
            with self.subTest(body=body):
                self.server.body = body
                result = self.run_script("cluster-status.sh")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn('"healthy": true', result.stdout)

    def test_cluster_health(self):
        for state, live, healthy in [("active", ["node1"], True),
                                     ("recovering", ["node1"], False),
                                     ("active", [], False)]:
            self.server.body = json.dumps({"responseHeader": {"status": 0}, "cluster": {
                "live_nodes": live, "collections": {"films": {"shards": {"shard1": {
                    "replicas": {"r1": {"node_name": "node1", "state": state,
                                        "leader": "true"}}}}}}}})
            result = self.run_script("cluster-status.sh")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["healthy"], healthy)

    def test_empty_cluster_is_valid(self):
        self.server.body = json.dumps({"responseHeader": {"status": 0},
                                       "cluster": {"live_nodes": [], "collections": {}}})
        result = self.run_script("cluster-status.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["healthy"])

    def test_scaling_flags(self):
        for value, expected in [(False, "false"), (True, "true"), (None, "true"), ("missing", "true")]:
            with self.subTest(value=value):
                scaling = {} if value == "missing" else {
                    "vacatePodsOnScaleDown": value, "populatePodsOnScaleUp": value}
                self.env["TEST_CR"] = json.dumps({"spec": {"scaling": scaling}})
                result = self.run_script("preflight.sh")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"vacatePodsOnScaleDown={expected} populatePodsOnScaleUp={expected}",
                              result.stdout)


if __name__ == "__main__":
    unittest.main()