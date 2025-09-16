# Trigger and Wait for Workflow Action

A reusable GitHub Action that triggers a workflow and waits for its completion with timeout protection and proper error handling.

## Features

- **Sequential Execution**: Prevents workflow collision by waiting for completion before proceeding
- **Timeout Protection**: Configurable timeout (default 30 minutes) to prevent infinite waiting
- **Error Handling**: Handles all workflow states including failure and cancellation
- **Clear Logging**: Provides detailed progress information with status updates and elapsed time tracking
- **Modular Design**: Single responsibility with clean input/output interface
- **Conditional Execution**: Only runs when changes are detected and auto-merge is enabled

## Usage

```yaml
- name: Trigger and Wait for Stage 2 Workflow
  uses: ./.github/actions/trigger-and-wait-workflow
  with:
    workflow-file: 'release-stage-2_build_and_release.yml'
    ref: 'latest'
    release-type: ${{ matrix.release_type }}
    scheduled: ${{ github.event_name == 'workflow_dispatch' && 'Manual' || 'Scheduled' }}
    github-token: ${{ secrets.GH_TOKEN }}
    changes-detected: ${{ steps.homebridge-bot.outputs.changes_detected }}
    auto-merge: ${{ steps.homebridge-bot.outputs.auto_merge }}
    timeout-minutes: '30'
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow-file` | Yes | - | The workflow file to trigger (e.g., `release-stage-2_build_and_release.yml`) |
| `ref` | Yes | `latest` | The git ref to run the workflow on |
| `release-type` | Yes | - | The release type parameter to pass to the workflow |
| `scheduled` | No | `Manual` | The scheduled parameter to pass to the workflow |
| `github-token` | Yes | - | GitHub token for authentication |
| `timeout-minutes` | No | `30` | Maximum wait time in minutes |

## Outputs

| Output | Description |
|--------|-------------|
| `workflow-conclusion` | The conclusion of the triggered workflow (`success`, `failure`, `cancelled`, etc.) |
| `run-id` | The run ID of the triggered workflow |

## How It Works

The action performs these steps sequentially:

1. **Trigger Workflow**: Uses `gh workflow run` to trigger the specified workflow
2. **Find Workflow Run**: Uses `gh run list` to locate the most recently triggered workflow
3. **Extract Run ID**: Extracts the run ID from the workflow URL using regex pattern matching
4. **Wait for Completion**: Polls workflow status using `gh run view` until completion with timeout protection

## Error Handling

- **Timeout**: If the workflow doesn't complete within the specified timeout, the action will exit with code 0 (non-failing timeout)
- **Workflow Failure**: If the triggered workflow fails, the action will exit with code 1
- **API Errors**: If GitHub CLI commands fail, the action will exit with code 1
- **Invalid URLs**: If the workflow URL cannot be parsed, the action will exit with code 1

## Implementation Details

Based on the GitHub CLI polling pattern recommended in [cli/cli#4001](https://github.com/cli/cli/issues/4001#issuecomment-2742170405), this action ensures sequential workflow execution to prevent collision during the publishing phase.

The action only executes when both `changes-detected` and `auto-merge` are `true`, making it safe to use in conditional scenarios where no action should be taken.