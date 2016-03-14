#!/bin/bash

mkdir datastore tm
rsync -av /var/lib/one/remotes/datastore/emc datastore/
rsync -av /var/lib/one/remotes/tm/emc tm/

