# Bonus: Run and test local GitLab

Complete P3 first. Run the commands from the main repository root, inside
your VM. Keep the P1/P2 VMs stopped to leave memory for GitLab. This lab sets
aside at least 3 GiB for GitLab alone; allow several minutes for first startup.

## 1. Start GitLab

```sh
bash bonus/scripts/setup.sh
kubectl config use-context k3d-iot-cluster
kubectl -n gitlab get pods,services,pvc
cat bonus/.secrets/root-password
```

The pod must show `1/1 Running` and the volume `Bound`. Open
`http://localhost:8081` inside the VM. Sign in as `root` with that password.
If you changed the password previously, use your current password.

GitLab runs in the `gitlab` namespace with persistent storage. The manifest
uses the official `gitlab/gitlab-ce:latest` image and pulls it when the pod
starts, as the subject asks for the latest release. Check the running version:

```sh
kubectl -n gitlab exec gitlab-0 -- cat /opt/gitlab/embedded/service/gitlab-rails/VERSION
```

## 2. Put the application in GitLab

In GitLab, choose **New project → Create blank project**:

- Name: `achraiti-iot`, under the `root` namespace.
- Visibility: **Public**, so Argo CD can read it without a token.
- Enable **Initialize repository with a README**; use branch `main`.

If `root/achraiti-iot` already exists, reuse it and check that it is public.
Clone it beside this repository and copy only the application manifests:

```sh
git clone http://root@localhost:8081/root/achraiti-iot.git ../achraiti-iot-gitlab
mkdir -p ../achraiti-iot-gitlab/p3/confs
cp p3/confs/deployment.yaml p3/confs/service.yaml p3/confs/kustomization.yaml \
  ../achraiti-iot-gitlab/p3/confs/
```

Start the bonus demonstration at `v1`:

```sh
cd ../achraiti-iot-gitlab
sed -i 's|wil42/playground:v2|wil42/playground:v1|' p3/confs/deployment.yaml
git add p3/confs
git commit -m 'Deploy v1'
git push origin main
cd -
```

Enter the GitLab root password if Git asks. If Git says there is nothing to
commit, the files already match; continue with the push. On subsequent runs,
reuse this checkout. `cd -` returns you to the main repository.

## 3. Connect Argo CD

```sh
kubectl apply -f bonus/confs/argocd-app.yaml
kubectl -n argocd get application wil-playground -w
```

Allow a few minutes for sync, then stop the watch with Ctrl+C. Verify:

```sh
kubectl -n argocd get application wil-playground \
  -o jsonpath='{.spec.source.repoURL}{"\n"}{.status.sync.revision}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
git -C ../achraiti-iot-gitlab rev-parse HEAD
curl -fsS http://localhost:8888/
```

Expected: the source is
`http://gitlab.gitlab.svc.cluster.local/root/achraiti-iot.git`, the commit
hashes match, status is `Synced Healthy`, and curl reports `v1`.
The internal GitLab address lets Argo CD reach GitLab from inside Kubernetes.

## 4. Test automatic deployment of v2

```sh
cd ../achraiti-iot-gitlab
sed -i 's|wil42/playground:v1|wil42/playground:v2|' p3/confs/deployment.yaml
git add p3/confs/deployment.yaml
git commit -m 'Deploy v2'
git push origin main
cd -
kubectl -n argocd get application wil-playground -w
```

Wait for sync and stop the watch with Ctrl+C. Repeat the three verification
commands in step 3: the commit hashes must match, status must be
`Synced Healthy`, and curl must now report `v2`. This demonstrates that the
local GitLab commit caused the deployment. Reverse `v2` to `v1`, commit and
push to test rollback.

## If something fails

```sh
kubectl -n gitlab describe pod gitlab-0
kubectl -n argocd describe application wil-playground
kubectl -n dev get pods
```

For GitLab startup failures, check the pod events for memory, disk or image
pull errors. For Argo CD repository errors, check public visibility, the
`main` branch and the three files under `p3/confs` in GitLab. If HTTP Git
authentication is disabled or you enabled 2FA, use a personal access token
with `write_repository` scope as the Git password.

To point the application back to GitHub, run from the main repository:

```sh
kubectl apply -f p3/confs/argocd-app.yaml
```

References: [GitLab container configuration](https://docs.gitlab.com/install/docker/installation/),
[Git authentication troubleshooting](https://docs.gitlab.com/topics/git/troubleshooting_git/).
