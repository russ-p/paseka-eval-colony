eval gate copy: {{len .Tasks}} task(s) on this trail
{{range .Tasks}}- {{.TaskID}} {{.Phase}} {{.Status}}
{{end}}
