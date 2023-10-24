#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2022 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2022 Buoyant Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.  You may obtain
# a copy of the License at
#
#     http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

clear

# Create a K3d cluster to use for our Argo setup.
CLUSTER=${CLUSTER:-argo}
# echo "CLUSTER is $CLUSTER"

# Ditch any old cluster...
k3d cluster delete $CLUSTER &>/dev/null

#@SHOW

# Don't install traefik or the metrics-server: we don't need them.
k3d cluster create $CLUSTER \
    --k3s-arg '--disable=traefik,metrics-server@server:*;agents:*'

#@wait
#@HIDE

# if [ -f images.tar ]; then k3d image import -c ${CLUSTER} images.tar; fi
# #@wait

# $SHELL $SETUP
