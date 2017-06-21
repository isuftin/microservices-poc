import falcon

from .hello_world import HelloWorld


api = application = falcon.API()

hi = HelloWorld()
api.add_route('/hello_world', hi)
