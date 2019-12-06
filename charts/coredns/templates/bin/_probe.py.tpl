#!/usr/bin/env python

import argparse
import requests
import socket
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

class httpHandler(BaseHTTPRequestHandler):
  def _set_headers(self):
    self.send_header('Content-type', 'text/html')
    self.end_headers()

  def do_GET(self):
    try:
      if self.path == '/externalhealth':
        failed = False
        res = requests.get("http://127.0.0.1:{}/health".format(args.check_port))
        if res.status_code >= 400:
          print('Failed /health check, status code = : {}'.format(res.status_code))
          failed = True

        with open(args.filename, 'r') as fh:
          for host in fh.read().splitlines():
            # ignore blank lines
            if not host:
              continue
            res = subprocess.run(
              ["host", "-W=2", "-R=1", host, "127.0.0.1"],
              stdout=subprocess.PIPE,
              stderr=subprocess.STDOUT)
            if res.returncode != 0:
              print('Failed to resolve host: "{}"'.format(host))
              print(res.stdout)
              failed = True
              break

        if failed:
          print('Check failed')
          self.send_response(500)
        else:
          self.send_response(200)
      elif self.path == '/selfcheck':
        self.send_response(200)
      else:
        print('Unsupported endpoint')
        self.send_response(404)
    except Exception as e:
      print(e)
      self.send_response(502)
    finally:
      self._set_headers()


def run(port='80'):
  print("Running...")
  httpd = HTTPServer(('', port), httpHandler)
  httpd.serve_forever()

if __name__ == "__main__":
  parser = argparse.ArgumentParser(description='Run name resolution for a list of names from the file')
  parser.add_argument('--filename', dest='filename', help='Path to file with names to resolve', required=True)
  parser.add_argument('--check-port', dest='check_port', help='Port to check for health', default=8080, type=int)
  parser.add_argument('--listen-port', dest='listen_port', help='Port to listen for health checks', default=8282, type=int)
  args = parser.parse_args()
  run(port=args.listen_port)
