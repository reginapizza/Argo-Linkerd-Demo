# Argo-Linkerd-Demo

### Prerequisites:
- A Kubernetes cluster of your choosing- for this demo we're using K3D running locally
- Install kubectl
- Install Helm
- Install step

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
step certificate create root.linkerd.cluster.local ca.crt ca.key \ --profile root-ca --no-password --insecure
```
Generate the issues certificate and key: 
```
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \ --profile intermediate-ca --not-after 8760h --no-password --insecure \ --ca ca.crt --ca-key ca.key
```
6. Add the Linkerd Helm repo
```
helm repo add linkerd https://helm.linkerd.io/stable
```
7. Install the linkerd-crds chart
```
helm install linkerd-crds linkerd/linkerd-crds -n linkerd --create-namespace
```
8. Install the linkerd-control-plane chart
```
helm install linkerd-control-plane -n linkerd \
 --set-file identityTrustAnchorsPEM=ca.crt \
 --set-file identity.issuer.tls.crtPEM=issuer.crt \
 --set-file identity.issuer.tls.keyPEM=issuer.key \
 linkerd/linkerd-control-plane
```
9. Clone the Linkerd examples repository to your local machine, and then `cd` into it and add the new remote endpoint 
```
git clone https://github.com/linkerd/linkerd-examples.git \
cd linkerd-examples \
git remote add git-server git://localhost/linkerd-examples.git
```
10. Deploy the Git server to the `scm` namespace in your cluster
```
kubectl apply -f gitops/resources/git-server.yaml
```
Then confirm that the git server is healthy:
```
kubectl -n scm rollout status deploy/git-server
```
11. Clone the example repo to your git server
```
git_server=`kubectl -n scm get po -l app=git-server -oname | awk -F/ '{ print $2 }'`

kubectl -n scm exec "${git_server}" -- \
  git clone --bare https://github.com/linkerd/linkerd-examples.git
```
Then confirm that the remote repo was successfully cloned: 
```
kubectl -n scm exec "${git_server}" -- ls -al /git/linkerd-examples.git
```
Now confirm that you can push from the local repo to the remote repo with port-forwarding:
```
kubectl -n scm port-forward "${git_server}" 9418  &

git push git-server master
```
12. Access the Argo CD Dashboard
First confirm that all argocd pods are ready with:
```
for deploy in "dex-server" "redis" "repo-server" "server"; \
  do kubectl -n argocd rollout status deploy/argocd-${deploy}; \
done

kubectl -n argocd rollout status statefulset/argocd-application-controller
```
Then use port-forwarding to access the Argo CD UI: 
```
kubectl -n argocd port-forward svc/argocd-server 8080:443  \
  > /dev/null 2>&1 &
```
The Argo CD UI should now be visible when you visit [https://localhost:8080/](https://localhost:8080/)

13. Log into Argo CD
To get the initial admin password, run:
```
argocd admin initial-password -n argocd
```
Then log into the UI with username as `admin` and the password from the output above.

Note: This password is meant to be used to log into initially, after that it is recommended that you delete the `argocd-initial-admin-secret` from the `argocd` namespace once you have changed the password. You can change the admin password with `argocd account update-password`. Since this is only for demo purposes, we will not be showing this. 

14. Authenticate the Argo CD CLI
```
password=`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

argocd login 127.0.0.1:8080 \
  --username=admin \
  --password="${password}" \
  --insecure
```
15. Now set up the `demo` project to group our applications:
```
kubectl apply -f gitops/project.yaml
```
This project defines the list of permitted resource kinds and target clusters that our applications can work with.

Now confirm that the project is deployed correctly with:
```
argocd proj get demo
```
If you refresh the UI, you should now see your demo project. 

16. Deploy the main application, which serves as a parent for all the other applications:
```
kubectl apply -f gitops/main.yaml
```
And now confirm that it deployed successfully:
```
argocd app get main
```
You can sync the main application either through the Argo CD UI, or with `argocd app sync main`. 

17. TBC...


