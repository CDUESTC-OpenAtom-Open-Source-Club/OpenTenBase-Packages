# OpenTenBase Docker Compose

One-command deployment of a complete OpenTenBase cluster.

## Cluster Architecture

```
                    ┌─────────┐
                    │   GTM   │ :6666
                    └────┬────┘
                         │
              ┌──────────┼──────────┐
              │          │          │
        ┌─────┴─────┐   │   ┌─────┴─────┐
        │ Datanode 1 │   │   │ Datanode 2 │
        │  :15432    │   │   │  :15433    │
        └───────────┘   │   └───────────┘
                        │
                  ┌─────┴─────┐
                  │Coordinator│
                  │   :5432   │
                  └───────────┘
```

## Quick Start

```bash
# Build and start
docker compose up -d

# Connect to coordinator
docker compose exec coordinator psql -U opentenbase -d postgres

# Check status
docker compose ps
```

## Build from Release Packages

```bash
# Download .deb packages into the runtime directory
cd ../runtime
curl -sLO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/opentenbase_5.0-1ubuntu1.noble_all.deb
curl -sLO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/opentenbase-server_5.0-1ubuntu1.noble_amd64.deb
curl -sLO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/opentenbase-client_5.0-1ubuntu1.noble_amd64.deb
curl -sLO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/opentenbase-contrib_5.0-1ubuntu1.noble_amd64.deb
cd ../compose

# Build and start
docker compose up -d --build
```

## Operations

### Connect to Coordinator
```bash
docker compose exec coordinator psql -U opentenbase -d postgres
```

### View Logs
```bash
docker compose logs -f gtm
docker compose logs -f coordinator
docker compose logs -f datanode1
```

### Stop Cluster
```bash
docker compose down
```

### Stop and Remove Data
```bash
docker compose down -v
```

### Restart a Node
```bash
docker compose restart datanode1
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| NODE_TYPE | - | Node type: `gtm`, `coordinator`, `datanode` |
| NODE_NAME | - | Node identifier |
| GTM_HOST | - | GTM hostname |
| GTM_PORT | 6666 | GTM port |
| COORD_PORT | 5432 | Coordinator port |
| DN_PORT | 15432 | Datanode port |

## Troubleshooting

### GTM not starting
```bash
docker compose logs gtm
# Check if port 6666 is available
```

### Coordinator can't connect to GTM
```bash
# Verify GTM is healthy
docker compose ps
docker compose exec coordinator ping gtm
```

### Datanode connection issues
```bash
# Check network connectivity
docker compose exec datanode1 ping gtm
```
