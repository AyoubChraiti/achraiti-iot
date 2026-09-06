# Inception-of-Things

Team login: **achraiti**. Subject version **4.0**. Run the labs inside a Linux VM.

| Part | Goal | How it works |
| --- | --- | --- |
| P1 | Connect two Kubernetes nodes | Vagrant creates a K3s server and an agent |
| P2 | Serve three websites | Ingress routes the HTTP Host header to a Service and its pods |
| P3 | Deploy from GitHub | Argo CD watches Git and applies the app configuration |
| Bonus | Deploy from local GitLab | The same Argo CD app watches a repository hosted in the cluster |

**Validation:** live testing is in progress. The final results will be recorded here.

## Prepare the host

The host needs nested virtualization (`/dev/kvm`), Vagrant, and the
`vagrant-libvirt` plugin. On a fresh Debian/Ubuntu host:

```sh
sudo apt-get update
sudo apt-get install -y vagrant qemu-kvm libvirt-daemon-system libvirt-clients libvirt-dev build-essential rsync
sudo systemctl enable --now libvirtd
vagrant plugin install vagrant-libvirt  # skip if already installed
```

Install Docker, K3d, kubectl, and the remaining tools:

```sh
sudo bash p3/scripts/install-tools.sh
```

Log out and back in so the new Docker/libvirt group membership takes effect.
Each Vagrant guest uses **1 CPU and 1024 MB RAM**. Run P1 and P2 separately because
they use the same IP. Stop their VMs before P3/bonus to free memory. GitLab can use
up to 5 GiB; this host has 9 GiB, so keep other heavy workloads closed.

## P1: K3s server and agent

```sh
cd p1
vagrant up --provider=libvirt --no-parallel
bash scripts/test.sh
vagrant ssh achraitiS -c 'kubectl get nodes -o wide'
vagrant ssh achraitiSW -c 'hostname; ip -4 addr'
vagrant halt
cd ..
```

Expected: `achraitis` at **192.168.56.110** and `achraitisw` at
**192.168.56.111**, both Ready. The Linux hostnames end in `S` and `SW`;
Kubernetes node names are lowercase to satisfy its naming rules.

The server runs the Kubernetes API and controllers. The agent joins using the
shared lab token. Vagrant manages passwordless SSH. K3s uses the private interface
for node and pod traffic; Vagrant also has a management interface for SSH/NAT.
Use kubectl on the server, which has the cluster credentials.

## P2: three applications and Ingress

```sh
cd p2
vagrant up --provider=libvirt
bash scripts/test.sh
curl -H 'Host: app1.com' http://192.168.56.110/
curl -H 'Host: app2.com' http://192.168.56.110/
curl -H 'Host: anything.example' http://192.168.56.110/
curl http://192.168.56.110/
vagrant ssh achraitiS -c 'kubectl get deploy,pods,svc,ingress'
vagrant halt
cd ..
```

Expected responses: **app1, app2, app3, app3**. App2 has **three Ready replicas**;
the others have one. Each app's YAML contains its HTML ConfigMap, Deployment,
and Service. The Ingress matches app1.com/app2.com and uses app3 for other hosts.

Request path: **client → Traefik Ingress → Service → pod**. The Deployment keeps
the requested number of pods running; the Service finds them using labels.
After editing files, run `vagrant rsync` then `vagrant provision`.

## P3: K3d and Argo CD

K3s is a lightweight Kubernetes distribution. K3d runs K3s nodes in Docker
containers, so this part needs no Vagrant guests. Argo CD continuously reconciles
Git's declared configuration with Kubernetes. This is continuous deployment;
the prebuilt application images mean no image-building pipeline is required.

The public repository is [AyoubChraiti/achraiti-iot](https://github.com/AyoubChraiti/achraiti-iot).
Argo CD reads branch `main`, directory `p3/confs`. Its Kustomize file selects only
the app Deployment and Service, keeping Argo CD's own configuration separate.

```sh
bash p3/scripts/setup.sh
bash p3/scripts/test.sh v1
kubectl --context k3d-iot-cluster get ns
kubectl --context k3d-iot-cluster -n argocd get applications
curl http://localhost:8888/
```

To open the dashboard, keep this command running in another terminal:

```sh
kubectl --context k3d-iot-cluster -n argocd port-forward svc/argocd-server 8080:443
```

Visit **https://localhost:8080**, accept the local certificate, and log in as
`admin`. Retrieve the initial password:

```sh
kubectl --context k3d-iot-cluster -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Demonstrate the required GitHub update from the repository root:

```sh
sed -i 's|wil42/playground:v1|wil42/playground:v2|' p3/confs/deployment.yaml
git add p3/confs/deployment.yaml
git commit -m 'Use playground v2'
git push origin main
bash p3/scripts/test.sh v2
```

Expect `{"status":"ok", "message":"v2"}`. Argo CD polls every 30 seconds and
then rolls out the image. The check verifies Git sync, health, rollout, image,
and HTTP response. To return to v1, reverse the edit, commit, push, and check v1.
Do not use `kubectl set image`: the change must come from Git.

## Bonus: local GitLab

Complete P3 first, then run:

```sh
bash bonus/scripts/setup.sh
bash bonus/scripts/set-version.sh v1
bash bonus/scripts/set-version.sh v2
```

GitLab runs in namespace **gitlab** using the latest official Community Edition
image. Its first boot can take several minutes. A StatefulSet and persistent
volume keep its configuration, database, and repositories across pod restarts.

Setup creates the public project `root/achraiti-iot`, commits the app manifests,
and switches the existing Argo CD Application from GitHub to GitLab. Inside the
cluster, Argo CD uses `gitlab.gitlab.svc.cluster.local`; localhost would point to
Argo CD's own pod. The version helper makes a real GitLab commit, then waits for
Argo CD to deploy it. You can also commit through GitLab's web editor.

Visit **http://localhost:8081**, username **root**. Read the password locally:

```sh
cat bonus/.secrets/root-password
```

Credentials are ignored by Git. The bootstrap API token expires after seven days;
rerun setup to renew it. Existing app manifests are preserved. Record GitLab's
installed version with:

```sh
kubectl --context k3d-iot-cluster -n gitlab exec gitlab-0 -- head -n 1 /opt/gitlab/version-manifest.txt
```

To switch Argo CD back to GitHub:

```sh
kubectl --context k3d-iot-cluster apply -f p3/confs/argocd-app.yaml
bash p3/scripts/test.sh
```

## Useful checks

- **Host permissions:** `id` should include `docker` and `libvirt`; log in again
  after installation if access is denied.
- **Failed pod:** `kubectl describe pod NAME -n NAMESPACE` explains scheduling or
  readiness failures; `kubectl logs NAME -n NAMESPACE` shows application errors.
- **Git sync failure:** `kubectl -n argocd describe application wil-playground`.
- **Stop/resume P3 and bonus:** `k3d cluster stop iot-cluster` /
  `k3d cluster start iot-cluster`. Deleting the cluster removes local GitLab data.
- **Old Vagrant guests:** changing the box name does not upgrade existing guests.
  Save needed data before explicitly destroying and recreating them.
- **Browser outside the host VM:** use SSH port forwarding:
  `ssh -L 8080:localhost:8080 -L 8888:localhost:8888 -L 8081:localhost:8081 USER@HOST_VM_IP`.

## References

[Subject tools: K3s](https://docs.k3s.io/quick-start),
[K3d networking](https://k3d.io/stable/usage/exposing_services/),
[Argo CD setup](https://argo-cd.readthedocs.io/en/stable/getting_started/),
[GitLab container](https://docs.gitlab.com/install/docker/installation/),
[GitLab memory settings](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/).
