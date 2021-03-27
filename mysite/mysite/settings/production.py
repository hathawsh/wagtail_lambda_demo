from .base import *
import os
import urllib.parse

DEBUG = False

SECRET_KEY = os.environ['DJANGO_SECRET_KEY']

DATABASES = {
    'default': {
        'ENGINE': os.environ['DJANGO_DB_ENGINE'],
        'NAME': os.environ['DJANGO_DB_NAME'],
        'USER': os.environ['DJANGO_DB_USER'],
        'PASSWORD': os.environ['DJANGO_DB_PASSWORD'],
        'HOST': os.environ['DJANGO_DB_HOST'],
        'PORT': os.environ['DJANGO_DB_PORT'],
    }
}

ALLOWED_HOSTS = []
for spec in os.environ['ALLOWED_HOSTS'].split():
    if '://' in spec:
        host = urllib.parse.urlsplit(spec).hostname
        ALLOWED_HOSTS.append(host)
    else:
        ALLOWED_HOSTS.append(spec)

STATIC_URL = os.environ['STATIC_URL']

# The static context processor provides STATIC_URL to templates
TEMPLATES[0]['OPTIONS']['context_processors'].append(
    'django.template.context_processors.static')
