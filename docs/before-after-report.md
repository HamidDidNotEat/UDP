# Before/after report

UDP can show what a run changed on your PC. The option is on the summary page and is ticked by default.

## How it works

1. **Before:** when you click Start, and before anything is changed, UDP measures the PC.
2. **The run:** every step runs as usual. At the end, UDP keeps a copy of itself in `C:\ProgramData\UDP\app` and registers a one-time task, `\UDP\Before and after report`. The task runs at your next sign-in, with administrator rights and no prompt.
3. **After the restart:** about a minute after you sign in, UDP opens a small "What changed" window. It removes the task straight away, so it only ever runs once.
4. **Waiting:** UDP waits until Windows has settled: the PC has been on for at least 4 minutes and the processor has stayed below 25% for 15 seconds. After 10 minutes it measures anyway.
5. **After:** UDP measures again, shows the comparison, and saves it in `C:\ProgramData\UDP\reports` as `report_<date>.json` and `report_<date>.txt`. Then it deletes its copy in `C:\ProgramData\UDP\app`.

Later, the welcome page shows when UDP last ran and has a button to open that report again.

## What is measured

| Measurement | How |
|-------------|-----|
| Running processes | Number of processes |
| RAM in use | Total memory minus free memory |
| Running services | Windows services in the *Running* state |
| Startup entries | Values in the `Run` keys (machine and user) plus files in the Startup folders |
| Desktop programs | Entries in *Settings > Apps* (uninstall entries that are not hidden components or updates) |
| Store apps | Installed Store packages, not frameworks or Windows system components |
| Free disk space | Free space on the system drive |

## How fair is the comparison?

- **The counts are exact:** apps, programs, startup entries and services. They change only because of what was removed or switched off.
- **RAM and processes depend on timing.** The "before" measurement is taken while UDP is running, at whatever point you started it. A PC that has been on for hours, with programs open, uses more RAM. The "after" measurement is taken right after a restart, once Windows has settled. The report shows how long the PC had been on each time, so treat the RAM figure as an estimate.
- **For the fairest RAM comparison:** restart the PC, wait a few minutes without opening anything, then start UDP.

## Turning it off

Untick *After the restart, show what changed* on the summary page. If you change your mind after a run, delete the task `\UDP\Before and after report` in Task Scheduler. UDP also removes it by itself the next time it starts.

## state.json

`C:\ProgramData\UDP\state.json` stores the "before" measurement and your last run, together with the browser policies UDP can undo. Please do not delete it: without it UDP cannot show the report or undo those policies.
