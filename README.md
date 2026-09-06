# Inception-of-Things

Team login: `achraiti`

Run each part separately. P1 and P2 use the same IP address, so stop one before
starting the other. P3 and the bonus use the Docker/K3d cluster.

## Requirements

Install Vagrant with the libvirt provider for P1 and P2. Install the P3 tools:

```sh
sudo bash p3/scripts/install-tools.sh
```

Log out and back in after installation so Docker and libvirt group membership
is active.

## P1: K3s and Vagrant

```sh
cd p1
vagrant up --provider=libvirt --no-parallel
vagrant halt
cd ..
```

This creates `achraitiS` at `192.168.56.110` and `achraitiSW` at
`192.168.56.111`. The first machine is the K3s server and the second is the
agent.

## P2: Three applications

```sh
cd p2
vagrant up --provider=libvirt
vagrant halt
cd ..
```

The Ingress routes `app1.com` to app1, `app2.com` to app2, and all other hosts
to app3. App2 has three replicas.

## P3: K3d and Argo CD

Publish this repository publicly as `AyoubChraiti/achraiti-iot` or update
`p3/confs/argocd-app.yaml` with your public repository URL. Then run:

```sh
bash p3/scripts/setup.sh
```

The application is available at `http://localhost:8888`. Argo CD is available
through a port-forward:

```sh
kubectl --context k3d-iot-cluster -n argocd port-forward svc/argocd-server 8080:443
```

Open `https://127.0.0.1:8080`. The username is `admin`; retrieve the password:

```sh
kubectl --context k3d-iot-cluster -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

To demonstrate Git deployment, change `v1` to `v2` in
`p3/confs/deployment.yaml`, commit and push to `main`, then run:

```sh
kubectl --context k3d-iot-cluster -n argocd get application wil-playground
kubectl --context k3d-iot-cluster -n dev get deployment wil-playground
curl http://localhost:8888/
```

## Bonus: Local GitLab

Complete P3 first, then run:

```sh
bash bonus/scripts/setup.sh
bash bonus/scripts/set-version.sh v1
bash bonus/scripts/set-version.sh v2
```

GitLab is available at `http://localhost:8081`. The username is `root`; the
password is stored in `bonus/.secrets/root-password`. The bonus creates a
public `root/achraiti-iot` project, points Argo CD at it, and verifies that
version changes are deployed from GitLab.
