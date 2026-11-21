# Trigger and Wait for Workflow Action

A local action that starts a workflow with `workflow_dispatch` and waits until that run has finished.

## Usage

```yaml
- name: Trigger and Wait for Stage 2 Workflow
  uses: ./.github/actions/trigger-and-wait-workflow
  with:
    workflow-file: 'release-stage-2_build_and_push_docker_images.yml'
    ref: 'latest'
    release-type: ${{ matrix.stream }}
    scheduled: ${{ github.event_name == 'workflow_dispatch' && 'Manual' || 'Scheduled' }}
    github-token: ${{ github.token }}
    timeout-minutes: '60'
    run-name: 'Scheduled - Build and Push ${{ matrix.stream }}'
```

The job that uses it needs `actions: write` for the token it passes in.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow-file` | Yes | - | The workflow file to trigger |
| `ref` | Yes | `latest` | The branch to run the workflow on |
| `release-type` | Yes | - | Passed to the workflow as `release_type` |
| `scheduled` | No | `Manual` | Passed to the workflow as `Scheduled` |
| `github-token` | Yes | - | Token used for the `gh` calls |
| `timeout-minutes` | No | `30` | Longest time to wait for the run |
| `run-name` | No | empty | Text that the name of the triggered run contains |

## Outputs

| Output | Description |
|--------|-------------|
| `workflow-conclusion` | The conclusion of the triggered run (`success`, `failure`, `cancelled` ...) |
| `run-id` | The ID of the triggered run |

## How It Works

1. **Trigger**: notes the ID of the newest existing run, then starts the workflow with `gh workflow run`.
2. **Find the run** (`find-run.sh`): looks for a run on the same branch, with `run-name` in its name, and with a higher ID than the one noted in step 1. So an older run with the same name is never picked.
3. **Wait** (`wait-for-run.sh`): asks for the status every 30 seconds until the run has finished.

## Exit Codes

The step **fails (exit code 1)** when:

- the workflow could not be started
- the new run does not show up in the run list within two minutes
- the run ends with anything other than `success` (failed, cancelled, skipped ...)
- the run is still going after `timeout-minutes`
- GitHub reports a status this action does not know

The step passes only when the run ends with `success`.

## Tests

`test/unit/workflow-scripts.test.sh` runs both scripts against a fake `gh`. Run all tests with `test/unit/run.sh`.
