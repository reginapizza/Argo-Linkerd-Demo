# Argo-Linkerd-Demo

### Prerequisites:
- A Kubernetes cluster of your choosing- for this demo we're using K3D running locally
- Install kubectl
- Install Helm
- Install step
- A fork of this repo

1. Install Argo CD in your cluster
```
kubectl create namespace argocd

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
This will create a new namespace, `argocd`, where Argo CD services and application resources will live.

2. Download the Argo CD CLI
View the latest version of Argo CD by running the following command: 
```
VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/') 
```
For Mac: 
```
curl -sSL -o argocd-darwin-amd64 https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-darwin-amd64
sudo install -m 555 argocd-darwin-arm64 /usr/local/bin/argocd 
rm argocd-darwin-arm64
```
For Linux: 
```
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```
3. Install the Linkerd CLI
```
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
```
Then add the binary to your PATH with `export PATH=$PATH:/home/rescott/.linkerd2/bin` 

Once installed, verify the CLI is running correctly with `linkerd version` (Note: It's ok if you get `Server version: unavailable`, that is expected) 

4. Validate you Kubernetes cluster to make sure you're able to install Linkerd
```
linkerd check --pre
```
You should have all the checks pass. If there are any checks that do not pass, make sure to follow the provided links in the output and fix those issues before proceeding

5. Generate certificates installing Linkerd with Helm (skip this if you have your own certificates already available)

Generate the trust anchor certificate:
```
step certificate create root.linkerd.cluster.local ca.crt ca.key --profile root-ca --no-password --insecure
```
Generate the issues certificate and key: 
```
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key --profile intermediate-ca --not-after 8760h --no-password --insecure --ca ca.crt --ca-key ca.key
```

6. Access the Argo CD Dashboard
First confirm that all argocd pods are ready with:
```
for deploy in "dex-server" "redis" "repo-server" "server"; \
  do kubectl -n argocd rollout status deploy/argocd-${deploy}; \
done

kubectl -n argocd rollout status statefulset/argocd-application-controller
```
Then use port-forwarding to access the Argo CD UI: 
```
kubectl -n argocd port-forward svc/argocd-server 8080:443 > /dev/null 2>&1 &
```
The Argo CD UI should now be visible when you visit [https://localhost:8080/](https://localhost:8080/)

7. Log into Argo CD
To get the initial admin password, run:
```
argocd admin initial-password -n argocd
```
Then log into the UI with username as `admin` and the password from the output above.

Note: This password is meant to be used to log into initially, after that it is recommended that you delete the `argocd-initial-admin-secret` from the `argocd` namespace once you have changed the password. You can change the admin password with `argocd account update-password`. Since this is only for demo purposes, we will not be showing this. 

8. Authenticate the Argo CD CLI
```
password=`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

argocd login 127.0.0.1:8080 \
  --username=admin \
  --password="${password}" \
  --insecure
```
9. Create the linkerd namespace
```
kubectl create namespace linkerd
```

10. Add the linkerd helm charts as a repo: 
```
argocd repo add https://helm.linkerd.io/stable --type helm --name stable
```

11. Add the `linkerd-crd` helm chart as an application:
```
argocd app create linkerd-crds --repo https://helm.linkerd.io/stable --helm-chart linkerd-crds --revision 1.8.0 --dest-namespace linkerd --dest-server https://kubernetes.default.svc
```

12. Add the `linkerd-control-plane` helm chart as an application:
```
argocd app create linkerd-control-plane     --repo https://helm.linkerd.io/stable     --helm-chart linkerd-control-plane     --revision 1.16.2     --dest-namespace linkerd     --dest-server https://kubernetes.default.svc     --helm-set identityTrustAnchorsPEM="$(cat ca.crt)"     --helm-set identity.issuer.tls.crtPEM="$(cat issuer.crt)"     --helm-set identity.issuer.tls.keyPEM="$(cat issuer.key)"
```

13. Sync both the applications.
```
`argocd app sync linkerd-crd linkerd-control-plane`
```
You should see them both in sync and healthy.

14. Get a list of your CRDs
```
kubectl get crds
```
15. Try deleting one of your CRDs, for instance, `httproutes.policy.linkerd.io`
```
kubectl delete crd httproutes.policy.linkerd.io
```
16. Go back to the Argo CD UI and refresh the `linkerd-crd` app. You will see that it becomes `Missing` and `OutOfSync`. 

17. Now sync the `linkerd-crd` app. You will see that it recovers and goes back to `Synced` and `Healthy`. If you go back to your terminal and run `kubectl get crds` again, you will see the CRD for `httproutes.policy.linkerd.io` back!

18.  Let's deploy the Faces demo application. Create the namespace `faces`:
```
kubectl create namespace faces
```
then create the application with: 
```
argocd app create faces-app   --repo https://github.com/[YOUR_USERNAME]/Argo-Linkerd-Demo.git   --path faces   --dest-namespace default   --dest-server https://kubernetes.default.svc   --revision HEAD
```
And now confirm that it deployed successfully:
```
argocd app get faces-app
```
You can sync the main application either through the Argo CD UI, or with `argocd app sync faces-app`. 

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




