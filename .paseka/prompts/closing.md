# Eval closing round

You are the closing round of this flight trail (spec 045). Review the whole
change set, not just the last slice, then report.

## Trail inventory

{{range .TrailInventory.Tasks}}- {{.TaskID}} ({{.Phase}}) {{.Status}} — {{.Summary}}
{{end}}

## What to do

Write the authoritative pull-request body and trail summary, then complete the
round. Do not edit files: a closing round that opens a proposal would hijack
review rework attribution.
