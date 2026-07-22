# HEP Training Helm Chart

A Helm chart for deploying the **HEP Training** application in Kubernetes/OpenShift.

## Overview

This Helm chart deploys HEP Training using a Kubernetes/OpenShift cluster.

DISCLAIMER: For the database backup, `kartoza:pg-backup:14-3.1` was not used in Kubernetes because of file system permission issues; instead, we used `pg_dump` along with a Kubernetes CronJob that performs a backup on Monday at 2:00 AM (see `templates/backup-cronjob.yaml`). To see how to access the backups, see the [backup wiki section](https://github.com/hep-training/hep-training-helm-chart/wiki/Backup).

The deployment can be done manually or using the CLI tool.

## Get started

To start deploying your project, check [our wiki](https://github.com/hep-training/hep-training-helm-chart/wiki).

## License

[BSD 3-Clause License](./LICENSE)
