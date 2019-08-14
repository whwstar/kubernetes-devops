#!/bin/bash

#!/bin/bash

set -x

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi

cd addons/dashboard
kubectl apply -f  .
