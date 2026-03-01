// Placeholder label script
// In the pr_target_unsafe.yml workflow, this runs AFTER checking out
// the PR head — meaning an attacker's modified version of this file
// would execute with base branch secrets and write permissions.
//
// This is the exact pattern GhostGates GHOST-WF-001 detects.

console.log("Labeling PR based on changed files...");
