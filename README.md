# Inception-of-Things

Team login: `achraiti`. Implementation follows subject **version 4.0**, including the bonus.

This is four small labs, completed in order. Run everything inside a Linux host VM.
Parts 1 and 2 create nested VMs through Vagrant/libvirt. Part 3 runs Kubernetes
nodes as Docker containers inside the host VM; it does not use Vagrant.

## What each part proves

| Part | Goal | Implementation | Completion check |
| --- | --- | --- | --- |
| `p1` | One K3s controller and one agent | Two Debian 13 Vagrant VMs, private IPs, shared join token | Two Ready nodes, correct IPs/roles, passwordless SSH |
| `p2` | Route HTTP requests to three apps | One K3s VM, three Nginx Deployments, Services, Traefik Ingress | `app1.com` → app1; `app2.com` → app2; everything else → app3; app2 has 3 Ready replicas |
| `p3` | Deploy and update from public GitHub | Docker + K3d, `argocd` and `dev` namespaces, automatic Argo CD sync | A Git commit changes the response from `v1` to `v2` |
| `bonus` | Repeat GitOps using local GitLab | GitLab in namespace `gitlab`, persistent disk, local Git repository | A GitLab commit changes the response from `v1` to `v2` |

**Current status:** implementation is present. Live completion is still pending.
The initial host inspection found no Docker/K3d/kubectl, no installed Vagrant boxes,
no libvirt permission for the current account, and interactive sudo authentication.
The configured public GitHub repository must also be created/published. Do not mark
the project complete until the checks below pass, including both version-change demos.

## 0. Prepare the host VM

The existing host is a KVM VM. Enable nested virtualization in its hypervisor for
Parts 1 and 2. Check `ls -l /dev/kvm` inside the host.

Use the existing Vagrant installation with the `vagrant-libvirt` plugin. On a fresh
Debian/Ubuntu host, install Vagrant and the libvirt provider prerequisites first:

```sh
sudo apt-get update
sudo apt-get install -y vagrant qemu-kvm libvirt-daemon-system libvirt-clients libvirt-dev build-essential rsync
sudo systemctl enable --now libvirtd
vagrant plugin install vagrant-libvirt   # skip if vagrant plugin list already shows it
```

Install the Part 3 tools and grant the current user Docker/libvirt access:

```sh
sudo bash p3/scripts/install-tools.sh
```

**Log out and back in** after installation. Check:

```sh
id
virsh -c qemu:///system list --all
docker info
vagrant plugin list
k3d version
kubectl version --client
```

The installer targets Debian/Ubuntu with systemd. It installs Docker from the OS
repository and verifies checksums for K3d and kubectl. Versions are in
`p3/confs/versions.env`; kubectl matches the K3s server version.

Each Vagrant guest uses 1 CPU and 1024 MB RAM, as advised by the subject. This is
below current upstream recommendations for a K3s server, so keep these labs small.
The host currently has about 9 GiB RAM. Run the parts in sequence and stop unused
VMs before Part 3/bonus. GitLab requests 3 GiB and can use up to 5 GiB. If it cannot
fit alongside the cluster, increase host RAM; 12 GiB or more is more comfortable.
Leave roughly 20 GiB of free disk for cluster/container images and GitLab data.

## 1. K3s and Vagrant

**Goal:** `achraitiS` controls the cluster; `achraitiSW` joins it as an agent.
Both machines can run pods, but only the server exposes the Kubernetes API.

```sh
cd p1
vagrant up --provider=libvirt --no-parallel
bash scripts/test.sh
vagrant ssh achraitiS
# Inside the server:
kubectl get nodes -o wide
exit
vagrant ssh achraitiSW -c 'hostname; ip -4 addr; systemctl is-active k3s-agent'
```

Expected nodes: `achraitis` at `192.168.56.110`, and `achraitisw` at
`192.168.56.111`. Linux hostnames retain `S` / `SW`; Kubernetes node names are
lowercase because Kubernetes requires DNS-compatible names.

Vagrant supplies SSH keys. The lab join token connects the worker to the server.
K3s installs kubectl; use it on the server, which has the cluster kubeconfig.
Both K3s node IPs and the Flannel network interface use the private lab network.
Vagrant also provides a management interface for SSH/NAT; inspect both with `ip a`.
Traefik, ServiceLB, and metrics-server are disabled in this part to reduce memory.
The readable server kubeconfig and fixed token are conveniences for this private lab.

Stop this part before starting Part 2, which reuses `192.168.56.110`:

```sh
vagrant halt
cd ..
```

If old Debian 12 VMs exist, changing `vm.box` does **not** upgrade them. After
saving anything you need inside those guests, explicitly destroy and recreate
them with `vagrant destroy` followed by `vagrant up --provider=libvirt --no-parallel`.
This deletes guest disks; do it only when ready to replace them.

## 2. Three applications and Ingress

**Goal:** explain the request path: client → Traefik Ingress → Service → app pod.
A Deployment maintains replicas; a Service selects pods by their `app` label;
Ingress selects a Service using the HTTP `Host` header.

```sh
cd p2
vagrant up --provider=libvirt
bash scripts/test.sh
curl -H 'Host: app1.com' http://192.168.56.110/
curl -H 'Host: app2.com' http://192.168.56.110/
curl -H 'Host: something-else.com' http://192.168.56.110/
curl http://192.168.56.110/
vagrant ssh achraitiS -c 'kubectl get deploy,pods,svc,ingress -o wide'
```

Expect app1, app2, app3, app3 respectively. `app2` must have **3/3** Ready replicas;
app1 and app3 have one each. The hostless Ingress rule handles the fallback.
Each site's HTML is stored in its ConfigMap alongside its Deployment and Service.

For a browser, optionally add `192.168.56.110 app1.com app2.com` to the host VM's
`/etc/hosts`. Curl's `Host` header already demonstrates the requirement without it.
After changing files, use `vagrant rsync` and `vagrant provision` to deploy them.

```sh
vagrant halt
cd ..
```

## 3. K3d, Argo CD, and GitHub

**K3s** is a lightweight Kubernetes distribution. **K3d** runs K3s nodes inside
Docker containers. **Argo CD** watches Git and reconciles the cluster to the declared
state. This project demonstrates continuous deployment (GitOps); it does not build
images or need a CI runner because the two images already exist.

### Publish the source

Create a **public** GitHub repository called `achraiti-iot` under `AyoubChraiti`
(or choose another name containing a team login and edit
`p3/confs/argocd-app.yaml`). The existing `IoT` repository name does not satisfy
this naming requirement. Anonymous checks could not access either repository at
implementation time; GitHub can return 404 for missing or private repositories.

Publish the reviewed project on the `main` branch. For example, after creating
an empty repository in GitHub:

```sh
git add .gitignore README.md p1 p2 p3 bonus
git commit -m "Complete IoT labs and local GitLab bonus"
git remote add deploy git@github.com:AyoubChraiti/achraiti-iot.git
git push -u deploy main
```

If the `deploy` remote already exists, inspect it with `git remote -v` and use
`git remote set-url deploy ...` if necessary. Authenticate with your own SSH key.
The repository can be cloned anonymously by Argo CD over HTTPS.

### Start and inspect

Run as your normal user after the host preparation:

```sh
bash p3/scripts/setup.sh
bash p3/scripts/test.sh v1
kubectl --context k3d-iot-cluster get ns
kubectl --context k3d-iot-cluster -n argocd get applications
kubectl --context k3d-iot-cluster -n dev get pods
curl http://localhost:8888/
```

The setup creates `iot-cluster`, installs Argo CD, and creates its Application.
It **does not directly apply the app Deployment**. Argo CD reads `p3/confs` from
Git and uses `kustomization.yaml` to select only `deployment.yaml` and
`service.yaml`. The Application and namespace manifests stay outside its ownership.
`prune` removes resources deleted from Git; `selfHeal` corrects cluster-side drift.

Port 8888 maps to the app's NodePort. Port 8081 is reserved for GitLab.
Both bind to the host VM's loopback address. Open the Argo CD dashboard in a
separate terminal and keep the forwarding command running:

```sh
kubectl --context k3d-iot-cluster -n argocd port-forward svc/argocd-server 8080:443
```

Visit **https://localhost:8080**, accept the local certificate, and log in as
`admin`. Retrieve the initial password in another terminal:

```sh
kubectl --context k3d-iot-cluster -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

If browsing from your physical computer, forward the host VM's loopback ports
with SSH: `ssh -L 8080:localhost:8080 -L 8888:localhost:8888 -L 8081:localhost:8081 USER@HOST_VM_IP`.

### Demonstrate the required update

Change the image in Git, commit, and push. Do not use `kubectl set image`:

```sh
sed -i 's|wil42/playground:v1|wil42/playground:v2|' p3/confs/deployment.yaml
git add p3/confs/deployment.yaml
git commit -m "Use playground v2"
git push deploy main
bash p3/scripts/test.sh v2
curl http://localhost:8888/
```

Expected response: `{"status":"ok", "message":"v2"}`. Argo CD polls every
30 seconds; reconciliation and image pulling take additional time. The check waits
for Synced/Healthy, a completed rollout, the correct image, and the HTTP response.
Restore `v1` with the inverse edit, commit, push, and run the check with `v1`.

## Bonus: local GitLab

**Goal:** replace GitHub with local GitLab as the app's source while keeping the
same Argo CD deployment workflow. Finish and verify Part 3 before switching.

```sh
bash bonus/scripts/setup.sh
bash bonus/scripts/test.sh
```

The script installs the official `gitlab/gitlab-ce:latest` image in namespace
`gitlab`. The first boot can take 10–30 minutes. It uses one StatefulSet with
persistent configuration, logs, repositories, and database data. A memory-backed
`/dev/shm` volume supplies the shared memory expected by the GitLab container.
`imagePullPolicy: Always` plus a restart on setup refreshes the latest stable image.
Record the installed version during the defense:

```sh
kubectl --context k3d-iot-cluster -n gitlab exec gitlab-0 -- head -n 1 /opt/gitlab/version-manifest.txt
```

The setup creates the public project `root/achraiti-iot`, commits the three app
manifests, and changes the **existing** Argo CD Application's repository URL.
Argo CD reaches GitLab through Kubernetes DNS
`gitlab.gitlab.svc.cluster.local`; localhost inside an Argo CD pod would refer
to that pod itself. Only one Application owns `dev/wil-playground`.

Visit **http://localhost:8081**, username `root`. Read the password locally:

```sh
cat bonus/.secrets/root-password
```

The bootstrap API token expires after seven days. Password/token files are ignored
by Git and readable only by your user. If the token expires, rerun setup to issue
a replacement; existing app manifests are preserved. HTTP/password conveniences
are intended for this loopback-accessible local lab.

Demonstrate both versions through real commits in the local GitLab repository:

```sh
bash bonus/scripts/set-version.sh v1
bash bonus/scripts/set-version.sh v2
curl http://localhost:8888/
```

The helper calls GitLab's repository API to commit the manifest change. Argo CD
then deploys it. You can also edit and commit `p3/confs/deployment.yaml` using the
GitLab web editor. GitLab CI/Runner is not needed for this deployment flow.

Return Argo CD to GitHub when needed:

```sh
kubectl --context k3d-iot-cluster apply -f p3/confs/argocd-app.yaml
bash p3/scripts/test.sh
```

## Troubleshooting and completion checklist

Static checks completed: ShellCheck and shell/Ruby syntax, YAML parsing, Kustomize
rendering, 17 standard Kubernetes resources against strict schemas, both Argo CD
Applications against the v3.5.2 CRD, and both Vagrantfiles with
`vagrant validate --ignore-provider`. Provider checks, provisioning, application
traffic, and GitOps updates still require live execution.

- **Permission denied on libvirt/Docker:** run the installer, then log out and back
  in. Confirm `id` includes `libvirt` and `docker`.
- **Old Vagrant guests:** their original box remains until explicitly recreated.
- **IP conflict:** halt Part 1 before Part 2, and vice versa.
- **Argo CD ComparisonError:** inspect `kubectl -n argocd describe application wil-playground`;
  verify repository visibility, `main`, and committed `p3/confs` files.
- **Pending / OOMKilled GitLab:** inspect `kubectl -n gitlab describe pod gitlab-0`
  and `kubectl -n gitlab logs gitlab-0 --tail=100`; free or increase host memory.
- **Unavailable localhost ports:** the cluster must have the mappings defined by
  the new setup script. An older cluster created by the previous script has
  different mappings. Do not delete a cluster containing GitLab data casually.
- **Stop without deleting data:** `k3d cluster stop iot-cluster`; resume with
  `k3d cluster start iot-cluster`. Deleting the cluster also removes its local
  GitLab storage; persistent here means across pod restarts, not cluster deletion.

Completion means every item below has been demonstrated:

- [ ] P1: Debian 13 guests, correct hostnames/IPs, passwordless SSH, controller + agent Ready.
- [ ] P2: three apps, app2 with three Ready replicas, all hostname/fallback checks pass.
- [ ] P3: public login-named GitHub repo, `argocd`/`dev`, Argo CD Synced/Healthy.
- [ ] P3: committed and pushed `v1` → `v2`, verified through HTTP.
- [ ] Bonus: latest local GitLab in `gitlab`, repository and persistent storage working.
- [ ] Bonus: GitLab `v1` → `v2` commit automatically deployed and verified through HTTP.

## References

- [Debian stable release](https://www.debian.org/releases/)
- [Debian 13 Vagrant box](https://portal.cloud.hashicorp.com/vagrant/discover/debian/trixie64)
- [K3s quick start](https://docs.k3s.io/quick-start)
- [K3s resource requirements](https://docs.k3s.io/installation/requirements)
- [K3d port mappings](https://k3d.io/stable/usage/exposing_services/)
- [Argo CD installation](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [GitLab official container](https://docs.gitlab.com/install/docker/installation/)
- [GitLab memory configuration](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/)
- [GitLab repository commits API](https://docs.gitlab.com/api/commits/)
