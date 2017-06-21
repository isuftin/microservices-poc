import datetime

import falcon
import ujson


class HelloWorld(object):

    def on_get(self, req, resp):
        utc_time = datetime.datetime.utcnow()
        utc_str = utc_time.strftime('%Y-%m-%d %H:%M:%S')
        doc = {'message': 'Hello World! The time is {} UTC.'.format(utc_str)}
        resp_body = ujson.dumps(doc, ensure_ascii=False)
        resp.body = resp_body
        resp.status = falcon.HTTP_200
