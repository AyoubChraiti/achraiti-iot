# Inception-of-Things

Team login: `achraiti`. Requirements: [subject](en.subject.pdf).

Run everything inside your Linux VM. Commands below start at the repository
root. P1 and P2 share `192.168.56.110`: halt one before starting the other.

## Prerequisites

For P1/P2, use a Debian/Ubuntu VM with nested virtualization enabled:

```sh
sudo apt-get update
sudo apt-get install -y vagrant vagrant-libvirt qemu-kvm libvirt-daemon-system rsync
sudo usermod -aG libvirt,kvm "$USER"
```

For P3 and the bonus, install Docker, K3d, kubectl, Git and curl:

```sh
sudo bash p3/scripts/install-tools.sh
```

Log out and back in to activate group membership. Tool versions are in
`p3/confs/versions.env`. Run cluster commands as your normal user.

## P1: Two K3s machines

```sh
cd p1
vagrant up --provider=libvirt --no-parallel
vagrant ssh achraitiS -c 'kubectl wait --for=condition=Ready nodes --all --timeout=180s; kubectl get nodes -o wide'
vagrant ssh achraitiS -c 'hostname; ip -4 address; systemctl is-active k3s'
vagrant ssh achraitiSW -c 'hostname; ip -4 address; systemctl is-active k3s-agent'
```

Validate: both SSH commands work without a password, both nodes are `Ready`,
and both services are `active`. Hostnames are `achraitiS` and `achraitiSW`;
node IPs are `192.168.56.110` and `192.168.56.111`. Kubernetes node names are
lowercase. The server has the `control-plane` role; the agent shows `<none>`.

```sh
vagrant halt
cd ..
```

## P2: Three applications and Ingress

```sh
cd p2
vagrant up --provider=libvirt
vagrant ssh achraitiS -c 'kubectl get nodes -o wide; kubectl get deployments,pods,services,ingresses'
vagrant ssh achraitiS -c 'kubectl describe ingress applications'
curl -fsS -H 'Host: app1.com' http://192.168.56.110/
curl -fsS -H 'Host: app2.com' http://192.168.56.110/
curl -fsS -H 'Host: unknown.com' http://192.168.56.110/
curl -fsS http://192.168.56.110/
```

Validate: the node is `Ready` at `192.168.56.110`, deployments show `1/1`,
`3/3`, `1/1` for app1, app2, app3. Responses contain `app1`, `app2`, `app3`,
`app3`, respectively. Show the Ingress rules during evaluation.

```sh
vagrant halt
cd ..
```

## P3: GitHub and Argo CD

Publish the project on the public GitHub repository named in
`p3/confs/argocd-app.yaml` (`AyoubChraiti/achraiti-iot`, branch `main`). If you
use another repository, update `repoURL`; its name must include a team login.
Push the application manifests before setup.

```sh
bash p3/scripts/setup.sh
kubectl config use-context k3d-iot-cluster
kubectl get namespaces
kubectl -n argocd get application wil-playground
kubectl -n dev get pods
curl -fsS http://localhost:8888/
```

Validate: namespaces `argocd` and `dev` exist, the application is `Synced` and
`Healthy`, its pod is ready, and curl returns `{"status":"ok", "message": "v1"}`.

Open the Argo CD dashboard by running this in a separate terminal:

```sh
kubectl --context k3d-iot-cluster -n argocd port-forward svc/argocd-server 8080:443
```

Visit `https://localhost:8080` inside the VM and accept its local certificate.
Username: `admin`. Retrieve the password in another terminal:

```sh
kubectl --context k3d-iot-cluster -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Demonstrate an update through GitHub:

```sh
sed -i 's|wil42/playground:v1|wil42/playground:v2|' p3/confs/deployment.yaml
git add p3/confs/deployment.yaml
git commit -m 'Deploy v2'
git push origin main
kubectl -n argocd get application wil-playground -w
```

Allow a few minutes for automatic sync, then stop the watch with Ctrl+C.
Compare the deployed revision with the commit you pushed, and check the response:

```sh
git rev-parse HEAD
kubectl -n argocd get application wil-playground \
  -o jsonpath='{.status.sync.revision}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
curl -fsS http://localhost:8888/
```

Validate: the two commit hashes match, status is `Synced Healthy`, and curl
reports `v2`. To demonstrate rollback, change `v2` back to `v1`, commit and
push again. Argo CD must deploy the change from Git.

## Bonus: Local GitLab

Follow [the bonus run-and-test guide](bonus/README.md) after validating P3.

To stop and resume P3/bonus while keeping their data:

```sh
k3d cluster stop iot-cluster
k3d cluster start iot-cluster
```
