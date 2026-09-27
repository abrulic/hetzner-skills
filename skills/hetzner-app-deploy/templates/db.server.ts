import { PrismaPg } from "@prisma/adapter-pg"
import { getServerEnv } from "~/env.server"
import { PrismaClient } from "./generated/client"

declare global {
	var __prismaClient: PrismaClient | undefined
}

const createPrismaClient = () => {
	const { DATABASE_URL } = getServerEnv()
	return new PrismaClient({ adapter: new PrismaPg({ connectionString: DATABASE_URL }) })
}

/**
 * Held on `globalThis` so hot reload reuses it. Vite re-evaluates this module whenever it
 * or anything it imports changes, and a fresh client each time opens a pool that nothing
 * disposes — connections climb until Postgres refuses them. Production evaluates the
 * module once, so it keeps a plain singleton and never populates the global.
 */
export const prisma = globalThis.__prismaClient ?? createPrismaClient()

if (getServerEnv().NODE_ENV !== "production") globalThis.__prismaClient = prisma
