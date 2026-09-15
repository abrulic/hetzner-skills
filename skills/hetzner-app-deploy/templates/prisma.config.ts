import { defineConfig } from "prisma/config"

// Prisma 7 no longer auto-loads .env; load it here so CLI commands (migrate/generate/seed)
// see DATABASE_URL. In CI/prod the file is absent and real env vars are used instead.
try {
	process.loadEnvFile()
} catch {
	// no .env file present — rely on the ambient environment
}

export default defineConfig({
	schema: "prisma/schema.prisma",
	datasource: {
		url: process.env.DATABASE_URL,
	},
	// Add once the app has a seed. Seed is one-shot in production.
	// migrations: { seed: "tsx prisma/seed.ts" },
})
