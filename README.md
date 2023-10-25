# Argo-Linkerd-Demo

<!-- @import demosh/check-requirements.sh -->

### Prerequisites:

- A Kubernetes cluster of your choosing: for this demo we're using K3D running
  locally.

- The `kubectl`, `argocd`, `linkerd`, and `step` CLIs.

- A fork of this repo.

These requirements will be checked automatically if you use `demosh` to run
this.

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

<!-- @wait_clear -->

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

<!-- @wait_clear -->

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

<!-- @wait_clear -->

### Sync both applications

This tells Argo CD to go ahead and make the cluster look like the applications
we've defined.

```bash
argocd app sync linkerd-crds linkerd-control-plane
```

You should see them both in sync and healthy in the Argo CD dashboard.

<!-- @wait_clear -->

## Argo CD will correct drift

Let's take a look at the Linkerd CRDs:

```bash
kubectl get crds | grep linkerd.io
```

We see a few different CRDs. Let's try deleting one -- a good candidate is
`httproutes.policy.linkerd.io` since it's not yet in use. (Kubernetes won't
allow deleting a CRD that is in use.)

```bash
kubectl delete crd httproutes.policy.linkerd.io
```

Go back to the Argo CD dashboard and refresh all the apps (there's a REFRESH
APPS button). You will see that the `linkerd-crd` app shows `Missing` and
`OutOfSync`.

<!-- @wait -->

To correct this, hit the `SYNC` button for the `linkerd-crd` app. You will see
that it recovers and goes back to `Synced` and `Healthy` -- and indeed, we can
see that Argo has replaced the missing CRD:

```bash
kubectl get crds | grep linkerd.io
```

<!-- @wait_clear -->

## Using Argo CD with GitHub

Let's deploy the Faces demo application from your clone of this repo.

```bash
kubectl create namespace faces
```

then create the application with:

```bash
argocd app create faces-app \
       --repo https://github.com/${USER}/Argo-Linkerd-Demo.git \
       --path faces \
       --dest-namespace default \
       --dest-server https://kubernetes.default.svc \
       --revision HEAD
```
And now confirm that it deployed successfully:

```bash
argocd app get faces-app
```

Finally, sync up Faces as well:

```bash
argocd app sync faces-app
```

You should see Faces sync'd in the browser, too.

<!-- @wait -->

### Now let's play around with Argo Rollouts!

19. First we need to install the argo-rollouts kubectl plugin. It is optional, but convenient for managing and visualizing rollout from the command line.

With Brew:
```
brew install argoproj/tap/kubectl-argo-rollouts
```
Manual:
```
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-darwin-amd64
```
(for Linux distros, replace `darwin` with `linux` in the above command)

Make the binary executable:
```
chmod +x ./kubectl-argo-rollouts-darwin-amd64
```

Move the binary to your PATH:
```
sudo mv ./kubectl-argo-rollouts-darwin-amd64 /usr/local/bin/kubectl-argo-rollouts
```

Ensure you have it working properly:
```
kubectl argo rollouts version
```
20. Create the namespace for argo-rollouts and install the CRDs:
```
kubectl create namespace argo-rollouts
```
```
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```
21. Apply the `rollout.yaml` and `service.yaml` file from this repository:
```
kubectl apply -f https://raw.githubusercontent.com/reginapizza/Argo-Linkerd-Demo/main/argo-rollouts/rollout.yaml
```
```
kubectl apply -f https://raw.githubusercontent.com/reginapizza/Argo-Linkerd-Demo/main/argo-rollouts/service.yaml
```
22. Now using the Argo Rollouts kubectl plugin, let's visualize the rollout as it deploys with:
```
kubectl argo rollouts get rollout faces-rollout --watch
```




