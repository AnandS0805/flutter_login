
const { Pool } = require('pg'); // PostgreSQL connection pool import kar rahe hain

const pool = new Pool({

    user: 'postgres', // PostgreSQL username
    host: 'localhost', // Database jis computer par hai
    database: 'flutter_login_db', // Existing database ka naam
    password: 'msquareinfotech', // PostgreSQL ka actual password
    port: 5432 // PostgreSQL ka default port

});


async function checkConnection() {

    try {

        const client = await pool.connect(); // Database connection ka wait karega

        console.log('Database connected successfully'); // Connection successful message

        client.release(); // Connection ko pool mein wapas bhejega

    } catch (err) {

        console.log('Database connection failed:', err.message); // Error handle karega

    }

}

checkConnection(); // Function ko execute karenge
module.exports = pool; // Pool ko dusri files mein use karne ke liye export kar rahe hain
