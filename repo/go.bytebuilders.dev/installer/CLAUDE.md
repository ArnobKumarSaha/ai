# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`install` is a collection of helm-charts.
You only need to focus on these charts : `ace`, `ace-installer`, `service-gateway-presets` & `service-gateway`.

## Common Commands

```bash
# Build
make build              # Build binary for current OS/ARCH
make fmt                # Format code (goimports, gofmt, shfmt)
make lint               # Run golangci-lint
```

## Architecture

### `ace-installer` chart:
Main chart that will be deployed to cluster using "helm install ace-installer" command.
It creates the 'ace', 'service-gateway-presets' & 'catalog-manager' chart.

### `ace` chart:
The main chart. It holds every yamls that actually run the full platform. 

#### ingress to gateway Conversion:
One of the major task for me is to move all existing users to gateway.
This the main flow that I am thinking of in the ingress conversion:

phase-1: Users are using Ingress. My users are currently in this section.

phase-2: Enable gateway besides with ingress. Lets say, the host is "dbaas.kubedb.cloud"
When both ingress & gateway are enabled in the ace cluster :
Ingress -> dbaas.kubedb.cloud -> ingress LB
Gateway -> ace.ace.dbaas.kubedb.cloud -> envoy LB

phase-3: Swtching moment
On ing to gw switching moment, user needs to two thing:
1) Delete the dbaas.kubedb.cloud dns.
2) create CNAME dbaas.kubedb.cloud -> ace.ace.dbaas.kubedb.cloud
So that they can continue to use their existing connected application with old url.

phase-4: Disable all ingress stuffs

### `service-gateway-presets` chart:
It create GatewayConfig & GatewayPresets. 'catalog-manager' chart watches the gatewayconfigs, & create the 'service-gateway' chart from its own values.

### `service-gateway` chart:
