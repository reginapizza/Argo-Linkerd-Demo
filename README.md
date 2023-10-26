# Argo-Linkerd-Demo

<!-- @import demosh/check-requirements.sh -->
<!-- @import demosh/check-github.sh -->

### Prerequisites:

- A Kubernetes cluster of your choosing: for this demo we're using K3D running
  locally.

- The `kubectl`, `argocd`, `linkerd`, and `step` CLIs.

- A fork of this repo.

These requirements will be checked automatically if you use `demosh` to run
this.

<!-- @start_livecast -->
<!-- @SHOW -->

## Verify that your cluster can run Linkerd

Start by making sure that your Kubernetes cluster is capable of running
Linkerd.

```bash
linkerd check --pre
```

You should have all the checks pass. If there are any checks that do not pass,
make sure to follow the provided links in the output and fix those issues
before proceeding.

<!-- @wait_clear -->

## Install Argo CD in your cluster

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

This will create a new namespace, `argocd`, where Argo CD services and
application resources will live, and install Argo CD itself. Wait for all the
Argo CD pods to be running:

```bash
kubectl -n argocd rollout status deploy,statefulset
```

Then use port-forwarding to access the Argo CD UI:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443 > /dev/null 2>&1 &
```

The Argo CD UI should now be visible when you visit https://localhost:8080/.

<!-- @browser_then_terminal -->

To get the initial admin password, run:

```bash
argocd admin initial-password -n argocd
```

Then log into the UI with username as `admin` and the password from the output
above.

Note: This password is meant to be used to log into initially, after that it
is recommended that you delete the `argocd-initial-admin-secret` from the
`argocd` namespace once you have changed the password. You can change the
admin password with `argocd account update-password`. Since this is only for
demo purposes, we will not be showing this.

<!-- @browser_then_terminal -->

We'll be using the `argocd` CLI for our next steps, which means that we need to authenticate the CLI:

```bash
password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

argocd login 127.0.0.1:8080 \
  --username=admin \
  --password="$password" \
  --insecure
```

<!-- @wait_clear -->

## Add ArgoCD apps for Linkerd

We have to add two ArgoCD applications for Linkerd: one for Linkerd's CRDs,
and one for Linkerd itself.

### Generate certificates for Linkerd

In the Real World, you'd do this by having ArgoCD install cert-manager for
you, but we'll just do it by hand for the moment. Start by creating the
certificates using `step`:

Generate the trust anchor certificate:

```bash
#@immed
mkdir -p keys
#@immed
rm -f keys/ca.crt keys/ca.key
step certificate create \
     --profile root-ca \
     --no-password --insecure \
     root.linkerd.cluster.local \
     keys/ca.crt keys/ca.key
```

Generate the identity issuer certificate and key:

```bash
#@immed
rm -f keys/issuer.crt keys/issuer.key
step certificate create \
     --profile intermediate-ca --not-after 8760h \
     --ca keys/ca.crt --ca-key keys/ca.key \
     --no-password --insecure \
     identity.linkerd.cluster.local \
     keys/issuer.crt keys/issuer.key
```

<!-- @wait_clear -->

### Create the `linkerd` namespace

We'll also create the `linkerd` namespace by hand, rather than having Argo CD
do it:

```bash
kubectl create namespace linkerd
```

### Add the `linkerd-crd` app

We'll tell Argo CD to use Helm to install Linkerd for us, so we'll start by
using `argocd` to register the Linkerd Helm chart repo:

```bash
argocd repo add https://helm.linkerd.io/stable --type helm --name linkerd-stable
```

Once that's done, we can define an Argo CD application for the `linkerd-crds`
Helm chart, version 1.8.0. This corresponds to Linkerd `stable-2.14.0`.

```bash
argocd app create linkerd-crds \
       --repo https://helm.linkerd.io/stable \
       --helm-chart linkerd-crds \
       --revision 1.8.0 \
       --dest-namespace linkerd \
       --dest-server https://kubernetes.default.svc
```

At this point, we should see the `linkerd-crds` application in the Argo
dashboard.

<!-- @browser_then_terminal -->

### Add the `linkerd-control-plane` app

This is the same as before, but for the Linkerd control plane itself. We use
the `linkerd-control-plane` chart, version 1.16.2, which is (again) Linkerd
`stable-2.14.0`. We also explicitly provide the certificates here, as values
for the chart.

```bash
argocd app create linkerd-control-plane \
       --repo https://helm.linkerd.io/stable \
       --helm-chart linkerd-control-plane \
       --revision 1.16.2 \
       --dest-namespace linkerd \
       --dest-server https://kubernetes.default.svc \
       --helm-set identityTrustAnchorsPEM="$(cat keys/ca.crt)" \
       --helm-set identity.issuer.tls.crtPEM="$(cat keys/issuer.crt)" \
       --helm-set identity.issuer.tls.keyPEM="$(cat keys/issuer.key)"
```

And now we should see the `linkerd-control-plane` application in the Argo
dashboard.

<!-- @browser_then_terminal -->

### Sync both applications

Both applications show up as `OutOfSync` and `Missing` -- this is because we
haven't actually installed anything yet. Let's go ahead and sync them both,
which tells Argo CD to go ahead and make the cluster look like the
applications we've defined.

```bash
argocd app sync linkerd-crds linkerd-control-plane
```

We can watch the sync progress from the Argo CD dashboard.

<!-- @browser_then_terminal -->

## Argo CD Application resources

Note that when you run `argocd app create`, what happens under the hood is
that Argo CD actually creates an Application resource in the cluster. For
example, here's the Application for the `linkerd-crds` app:

```bash
kubectl get application -n argocd linkerd-crds -o yaml | bat -l yaml
```

So far we've shown using the `argocd` command line to create Applications in
this demo, but you can also commit the Application resources to Git and use
Argo CD to support a workflow that uses GitOps for everything. This is very
common in production use cases.

<!-- @wait_clear -->

We'll use this approach to install Emissary-ingress so that we can have access
to Faces without a port-forward. Here's our Application:

```bash
bat emissary/emissary-app.yaml
```

It has two separate `sources`: we've pulled YAML for Emissary's namespace and
CRD definitions into our `emissary-app` directory, and we use a Helm chart for
the rest. Let's go ahead and apply that:

```bash
kubectl apply -f emissary/emissary-app.yaml
```

Then we can sync it. We'll go manage that from the GUI.

<!-- @browser_then_terminal -->

## Argo CD will correct drift

One of the major things that Argo CD can do is to correct drift between what's
actually in the cluster, and what you want to be in the cluster. For example,
let's take a look at the Linkerd CRDs:

```bash
kubectl get crds | grep linkerd.io
```

We see a few different CRDs, all of which were installed when we synced the
`linkerd-crds` app. Let's try deleting one -- a good candidate is
`httproutes.policy.linkerd.io` since it's not yet in use. (Kubernetes won't
allow deleting a CRD that is in use.)

```bash
kubectl delete crd httproutes.policy.linkerd.io
```

Go back to the Argo CD dashboard and refresh all the apps (there's a REFRESH
APPS button). You will see that the `linkerd-crd` app shows `Missing` and
`OutOfSync`.

<!-- @browser_then_terminal -->

To correct this, hit the `SYNC` button for the `linkerd-crd` app. You will see
that it recovers and goes back to `Synced` and `Healthy`.

<!-- @browser_then_terminal -->

And indeed, we can see that Argo has replaced the missing CRD:

```bash
kubectl get crds | grep linkerd.io
```

<!-- @wait_clear -->

## Using Argo CD with GitHub

Now that we have Linkerd running, let's use Argo CD to deploy our Faces demo
application. Rather than basing it on a Helm chart, we'll instead use
manifests stored in our GitHub repo. The manifests live in the `faces`
directory:

```bash
ls -l faces
```

We have several files here:

- `namespace.yaml` creates the `faces` namespace and configures it for Linkerd
  auto-injection.

- `faces-gui.yaml` contains everything needed for the `faces-gui` workload,
  which serves the HTML and JavaScript of the Faces SPA.

- `face.yaml`, `smiley.yaml`, and `color.yaml` contain the Services,
  Deployments, and HTTPRoutes for our Faces demo workloads, except that

- `color-route.yaml` contains the HTTPRoute for the `color` workload.

<!-- @wait_clear -->

We'll start by defining our Argo CD application:

```bash
argocd app create faces-app \
       --repo https://github.com/${GITHUB_USER}/Argo-Linkerd-Demo.git \
       --path faces \
       --dest-namespace faces \
       --dest-server https://kubernetes.default.svc \
       --revision HEAD
```

We can make sure it deployed successfully with `argocd app get`.

```bash
argocd app get faces-app
```

Of course, we can also see it in the dashboard.

<!-- @browser_then_terminal -->

Finally, we can sync it up with `argocd app sync`, as before.

```bash
argocd app sync faces-app
```

You should see Faces sync'd in the browser, too. Let's start by checking
Faces' Pods:

```bash
kubectl rollout status -n faces deploy
kubectl get pods -n faces
```

That looks good. Note that each Pod has two containers: one is the application
container, the other is the Linkerd proxy.

Since we have Faces running behind Emissary, and we created this k3d cluster
to expose Emissary's loadbalancer to our host, we can access Faces from our
browser without a port-forward. Let's do that now.

<!-- @browser_then_terminal -->

So Faces is running, but it's weird that we're getting grey backgrounds: they
should be green, and the grey background implies that the `face` workload
can't talk to the `color` workload. Let's take a quick look at the `color`
HTTPRoute.

```bash
kubectl get httproutes.gateway.networking.k8s.io -n faces color-route -o yaml \
    | bat -l yaml
```

Ah, there's a typo in the `backendsRef` -- it says `colorr` with two `r`s,
instead of `color`. We can fix that by committing a fixed HTTPRoute to GitHub
and then re-syncing our app. Here's the fixed HTTPRoute:

```bash
bat faces-02-fixed-route/color-route.yaml
```

We can copy that into the directory that Argo CD is using, then commit and
push:

```bash
cp faces-02-fixed-route/color-route.yaml faces/color-route.yaml
git diff faces/color-route.yaml
git add faces/color-route.yaml
git commit -m "Fix color-route backendRef"
git push
```

Once that's done, let's resync the app.

```bash
argocd app sync faces-app
```

Now we should see that all is well from the browser.

<!-- @browser_then_terminal -->

### Now let's play around with Argo Rollouts!

Argo Rollouts are a nice progressive delivery tool. We'll use it to show
progressive delivery of the `color` workload, down in the Faces call graph.

First, let's install Argo Rollouts. We'll start by creating its namespace and applying Rollouts itself:

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

Next, since we want to use Gateway API to handle routing during progressive
delivery, we need to apply some configuration. First is RBAC to allow Argo
Rollouts to manipulate Gateway API HTTPRoutes.

```bash
kubectl apply -f argo-rollouts/rbac.yaml
```

After that is a ConfigMap that tells Argo Rollouts to use its Gateway API
plugin for routing.

```bash
bat argo-rollouts/configmap.yaml
kubectl apply -f argo-rollouts/configmap.yaml
```

Finally, we need to restart Rollouts to pick up the new configuration. (We
need to install Rollouts before applying the configuration because the
Rollouts RBAC relies on the ServiceAccount created when we install Rollouts!)

```bash
kubectl rollout restart  -n argo-rollouts deployment
kubectl rollout status  -n argo-rollouts deployment
```

<!-- @wait_clear -->

### Switching Faces to include Rollouts

We're going to switch Faces to use Argo Rollouts for the `color` workload. We
could do this by copying files into the `faces` directory -- but it's more
clear for people reading this demo repo to edit the `faces` Application to
point to the `faces-rollouts` directory in the repo, which we've already set
up for Rollouts.

Just change the `path` to `faces-rollouts` and we should be good to go.

```bash
kubectl edit application -n argocd faces-app
```

Now we can resync the `faces` app. Note the new `--prune` flag, which tells
Argo CD to delete any resources that are no longer in the app (specifically,
the old `color` Deployment, which has been replaced by the `color-rollout`
Rollout).

```bash
argocd app sync faces-app --prune
```

<!-- @wait_clear -->

Once that's done, we can look at the status of the `color-rollout` Rollout. It
should show that its `stable` version is running.

```bash
kubectl argo rollouts -n faces get rollout color-rollout
```

<!-- @wait_clear -->
<!-- @show_composite -->

### Rolling out a new version of `color`

To roll out a new version, we just need to edit the Rollout to reflect the new
version we want, and then let Argo Rollouts take it from there. Let's switch
our green color to purple: just change the value of the `COLOR` environment
variable to `purple`.

```bash
kubectl edit rollout -n faces color-rollout
```

Now using the Argo Rollouts kubectl plugin, let's visualize the rollout as it
deploys with. Once you start seeing some purple, you can use ^C to interrupt the watch.

```bash
kubectl argo rollouts -n faces get rollout color-rollout --watch
```

Note that shows as Paused. Why?

<!-- @wait_clear -->

### Promoting the rollout

If you look at the Rollout, you'll see this definition for the steps of the
rollout:

```
      steps:
        - setWeight: 30
        - pause: {}
        - setWeight: 40
        - pause: { duration: 15 }
        - setWeight: 60
        - pause: { duration: 15 }
        - setWeight: 80
        - pause: { duration: 15 }
```

<!-- @wait -->

Since there's no `duration` on the first `pause`, the rollout will pause until
we explicitly promote it. Let's do that now.

```bash
kubectl argo rollouts -n faces promote color-rollout
```

Now we can run the watch again, and we'll see it continuing along until we
have all purple, and the canary is scaled down.

```bash
kubectl argo rollouts -n faces get rollout color-rollout --watch
```

<!-- @clear -->

## Summary

So that's a whirlwind tour of ArgoCD with Linkerd -- and note that we didn't
use SMI at all, just Linkerd's native Gateway API support! Obviously, this is
a very quick tour rather than a production-ready setup, but hopefully it gives
you a sense of how Argo CD can be used to manage Linkerd and your
applications.

You can find the source for this demo at

https://github.com/reginapizza/Argo-Linkerd-Demo/

and we welcome feedback!
