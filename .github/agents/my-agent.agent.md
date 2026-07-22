{
	"mcpServers": {
			"github-mcp-server": {
			"type": "http",
			"url": "https://api.githubcopilot.com/mcp",
			"tools": ["*"],
			"headers": {
				"X-MCP-Toolsets": "issues,pull_requests,repos,actions"
			}
		}
	}
}
