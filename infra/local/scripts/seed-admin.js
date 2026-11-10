/* Idempotent demo seed: creates one tenant and one admin user.
 * Runs inside the auth-service image, which provides `pg` and `bcryptjs`.
 */
const { Client } = require("pg");
const bcrypt = require("bcryptjs");

const required = (name, fallback) => {
    const value = process.env[name] || fallback;
    if (!value) throw new Error(`Missing required environment variable: ${name}`);
    return value;
};

async function main() {
    const client = new Client({
        host: required("DB_HOST", "postgres"),
        port: Number(required("DB_PORT", "5432")),
        user: required("DB_USERNAME", "mernspace"),
        password: required("DB_PASSWORD", "mernspace"),
        database: required("DB_NAME", "mernspace_auth"),
    });

    await client.connect();

    const tenantName = required("TENANT_NAME", "Demo Restaurant");
    const tenantAddress = required("TENANT_ADDRESS", "1 Demo Street");

    let tenant = await client.query("SELECT id FROM tenants WHERE name = $1 LIMIT 1", [tenantName]);
    if (tenant.rowCount === 0) {
        tenant = await client.query(
            'INSERT INTO tenants(name, address) VALUES ($1, $2) RETURNING id',
            [tenantName, tenantAddress],
        );
    }
    const tenantId = tenant.rows[0].id;

    const email = required("ADMIN_EMAIL", "admin@mernspace.local").toLowerCase();
    const password = required("ADMIN_PASSWORD", "Admin@12345");
    const firstName = required("ADMIN_FIRST_NAME", "Demo");
    const lastName = required("ADMIN_LAST_NAME", "Admin");
    const passwordHash = await bcrypt.hash(password, 10);

    await client.query(
        `INSERT INTO users("firstName", "lastName", email, password, role, "tenantId")
         VALUES ($1, $2, $3, $4, 'admin', $5)
         ON CONFLICT (email) DO UPDATE
           SET "firstName" = EXCLUDED."firstName",
               "lastName"  = EXCLUDED."lastName",
               password    = EXCLUDED.password,
               role        = 'admin',
               "tenantId"  = EXCLUDED."tenantId"`,
        [firstName, lastName, email, passwordHash, tenantId],
    );

    console.log(`Seeded tenant "${tenantName}" (id=${tenantId}) and admin ${email}`);
    await client.end();
}

main().catch((err) => {
    console.error("Seed failed:", err.message);
    process.exit(1);
});
