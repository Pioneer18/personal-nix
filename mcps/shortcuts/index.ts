#!/usr/bin/env node
// shortcuts-mcp — MCP server wrapping macOS Shortcuts.app.
// Exposes every installed Shortcut as a callable tool via two operations:
//   - list: enumerate all installed Shortcuts by name
//   - run:  execute a Shortcut by name (with optional text input)
//
// macOS Shortcuts CLI reference:
//   shortcuts list                        — print all Shortcut names, one per line
//   shortcuts run "<name>"                — run a Shortcut
//   shortcuts run "<name>" --input-path - — pipe input via stdin

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";

const execFileP = promisify(execFile);

const server = new Server(
  { name: "shortcuts-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "list",
      description:
        "List all macOS Shortcuts installed on this Mac. Returns each Shortcut's name. Use to discover what Shortcuts are callable before invoking `run`.",
      inputSchema: {
        type: "object",
        properties: {},
        required: [],
      },
    },
    {
      name: "run",
      description:
        "Run a macOS Shortcut by exact name. Optionally pipe text input to the Shortcut (for Shortcuts that accept input, e.g. 'Save to Reading List'). Returns the Shortcut's stdout output, if any.",
      inputSchema: {
        type: "object",
        properties: {
          name: {
            type: "string",
            description: "The exact name of the Shortcut (case-sensitive, as shown by `list`).",
          },
          input: {
            type: "string",
            description:
              "Optional text input. Passed to the Shortcut via stdin. Omit if the Shortcut takes no input.",
          },
        },
        required: ["name"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;

  switch (name) {
    case "list": {
      const { stdout } = await execFileP("shortcuts", ["list"], { maxBuffer: 1024 * 1024 });
      const names = stdout.split("\n").map((s) => s.trim()).filter(Boolean);
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({ count: names.length, shortcuts: names }, null, 2),
          },
        ],
      };
    }

    case "run": {
      const shortcutName = (args as { name?: unknown })?.name;
      const input = (args as { input?: unknown })?.input;

      if (typeof shortcutName !== "string" || shortcutName.length === 0) {
        throw new Error("'name' is required and must be a non-empty string");
      }

      if (input !== undefined && typeof input !== "string") {
        throw new Error("'input', if provided, must be a string");
      }

      const cliArgs = ["run", shortcutName];
      if (typeof input === "string" && input.length > 0) {
        cliArgs.push("--input-path", "-");
      }

      const result = await new Promise<{ stdout: string; stderr: string; code: number | null }>(
        (resolve, reject) => {
          const child = spawn("shortcuts", cliArgs, { stdio: ["pipe", "pipe", "pipe"] });
          let stdout = "";
          let stderr = "";
          child.stdout.on("data", (chunk) => (stdout += chunk.toString()));
          child.stderr.on("data", (chunk) => (stderr += chunk.toString()));
          child.on("error", reject);
          child.on("close", (code) => resolve({ stdout, stderr, code }));
          if (typeof input === "string" && input.length > 0) {
            child.stdin.write(input);
          }
          child.stdin.end();
        },
      );

      if (result.code !== 0) {
        throw new Error(
          `Shortcut "${shortcutName}" failed (exit ${result.code}): ${result.stderr.trim() || "(no stderr)"}`,
        );
      }

      const output = result.stdout.trim() || result.stderr.trim();
      return {
        content: [
          {
            type: "text",
            text: output || `Shortcut "${shortcutName}" ran with no output.`,
          },
        ],
      };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
