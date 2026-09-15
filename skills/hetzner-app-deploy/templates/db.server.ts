import { PrismaPg } from "@prisma/adapter-pg"
import { getServerEnv } from "~/env.server"
import { PrismaClient } from "./generated/client"

const createPrismaClient = () => {
	const { DATABASE_URL } = getServerEnv()
	return new PrismaClient({ adapter: new PrismaPg({ connectionString: DATABASE_URL }) })
}

export const prisma = createPrismaClient()
