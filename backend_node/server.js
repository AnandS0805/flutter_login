
// Is file ka kaam API requests receive karna aur response dena hai.

// Responsibilities:
// - API routes banana (/register, /login, /refresh, /profile)
// - Flutter se data receive karna
// - Validation karna
// - Database functions call karna
// - Success ya error response bhejna

require('dotenv').config();

console.log('JWT SECRETKEY LOADED', !!process.env.JWT_SECRET);

const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const pool = require('./config/db');
const authMiddleware = require('./middleware/authMiddleware');
const crypto = require('crypto');

const app = express();

app.use(express.json());


// ======================================
// LOGIN ATTEMPTS MANAGEMENT
// ======================================

// Map temporary memory storage hai.
// Ismein IP address ke against failed login attempts store honge.
const loginAttempts = new Map();


// Ye function wrong email aur wrong password dono ke liye chalega.
function handleFailedLogin(ip, attemptData, res) {

    attemptData.attempts++; // Failed login count +1

    // 4th failed attempt par 15 minutes ke liye lock
    if (attemptData.attempts >= 4) {

        attemptData.lockUntil = Date.now() + 15 * 60 * 1000;

        return res.status(429).json({
            success: false,
            locked: true,
            message: 'Too many failed attempts. Login locked for 15 minutes.',
            retryAfterSeconds: 900
        });
    }

    // 1st, 2nd aur 3rd failed attempt ka response
    return res.status(401).json({
        success: false,
        message: 'Invalid email or password',
        remainingAttempts: 4 - attemptData.attempts,

        // Sirf 3rd failed attempt par warning
        warning: attemptData.attempts === 3
            ? 'Only 1 attempt remaining!'
            : null
    });
}


// ======================================
// HOME API
// ======================================

app.get('/', (req, res) => {

    res.send('Node.js Backend is Running!');

});


// ======================================
// REGISTER API
// ======================================

app.post('/register', async (req, res) => {

    try {

        const userData = req.body;

        // Check karna ki saare required fields mile hain ya nahi
        if (
            !userData.name ||
            !userData.email ||
            !userData.mobile ||
            !userData.password ||
            !userData.confirmPassword
        ) {
            return res.status(400).send('All Fields Are Required');
        }

        // Password aur confirm password match karna
        if (userData.password !== userData.confirmPassword) {
            return res.status(400).send('Password Does Not Match');
        }

        // Check karna ki email pehle se registered hai ya nahi
        const email_check = await pool.query(
            'SELECT * FROM users WHERE email = $1',
            [userData.email]
        );

        if (email_check.rows.length > 0) {
            return res.status(400).send('Email already registered');
        }

        // Password ko hash karna
        const hashedpassword = await bcrypt.hash(userData.password, 10);

        // User ko database mein insert karna
        const addUser = await pool.query(
            'INSERT INTO users(name,email,mobile,password_hash) VALUES($1,$2,$3,$4) RETURNING id,name,email,mobile',
            [
                userData.name,
                userData.email,
                userData.mobile,
                hashedpassword
            ]
        );

        // Flutter ko successful registration response bhejna
        return res.status(201).json({
            success: true,
            message: 'Registration Successful',
            user: addUser.rows[0]
        });

    } catch (e) {

        console.log('Register Error:', e.message);

        return res.status(500).json({
            success: false,
            message: 'Internal Server Error'
        });

    }

});


// ======================================
// LOGIN API
// ======================================

app.post('/login', async (req, res) => {

    try {

        const ip = req.ip; // Login request bhejne wale client ka IP

        const userData = req.body || {};

        const email = userData.email;
        const password = userData.password;

        // Is IP ka previous attempt data Map se lena
        let attemptData = loginAttempts.get(ip);

        // Agar IP pehli baar request bhej raha hai toh initial data create karo
        if (!attemptData) {

            attemptData = {
                attempts: 0,
                lockUntil: null
            };

            loginAttempts.set(ip, attemptData);
        }


        // ======================================
        // ACTIVE LOCK CHECK
        // ======================================

        // Check karna ki user abhi lock mein hai ya nahi
        if (
            attemptData.lockUntil &&
            Date.now() < attemptData.lockUntil
        ) {

            const remainingTime = Math.ceil(
                (attemptData.lockUntil - Date.now()) / 1000
            );

            return res.status(429).json({
                success: false,
                locked: true,
                message: 'Too many failed attempts. Try again after 15 minutes.',
                retryAfterSeconds: remainingTime
            });
        }


        // ======================================
        // EXPIRED LOCK RESET
        // ======================================

        // Agar 15 minutes complete ho gaye toh counter reset
        if (
            attemptData.lockUntil &&
            Date.now() >= attemptData.lockUntil
        ) {

            attemptData.attempts = 0;
            attemptData.lockUntil = null;
        }


        // ======================================
        // EMPTY FIELD CHECK
        // ======================================

        // Empty email/password request ko bhi failed attempt count karna
        if (!email || !password) {

            return handleFailedLogin(ip, attemptData, res);
        }


        // ======================================
        // EMAIL CHECK
        // ======================================

        // Database mein email search karna
        const check_email = await pool.query(
            'SELECT * FROM users WHERE email = $1',
            [email]
        );

        // Email nahi mila toh failed attempt count
        if (check_email.rows.length === 0) {

            return handleFailedLogin(ip, attemptData, res);
        }


        // ======================================
        // PASSWORD CHECK
        // ======================================

        // Entered password ko database ke hashed password se compare karna
        const check_pass = await bcrypt.compare(
            password,
            check_email.rows[0].password_hash
        );

        // Password galat hai toh failed attempt count
        if (!check_pass) {

            return handleFailedLogin(ip, attemptData, res);
        }


        // ======================================
        // SUCCESSFUL LOGIN
        // ======================================

        // Access token generate karna
        const token = jwt.sign(
            { user_id: check_email.rows[0].id },
            process.env.JWT_SECRET,
            { expiresIn: '15s' }
        );


        // Refresh token generate karna
        const refreshToken = jwt.sign(
            { user_id: check_email.rows[0].id },
            process.env.JWT_REFRESH_SECRET,
            { expiresIn: '7d' }
        );


        // Refresh token ka SHA256 hash banana
        const tokenhash = crypto
            .createHash('sha256')
            .update(refreshToken)
            .digest('hex');


        // Refresh token ki expiry date calculate karna
        const expiresAt = new Date(
            Date.now() + 7 * 24 * 60 * 60 * 1000
        );


        // Refresh token ko database mein save karna
        await pool.query(
            'INSERT INTO refresh_tokens(user_id,token_hash,expires_at) VALUES($1,$2,$3)',
            [
                check_email.rows[0].id,
                tokenhash,
                expiresAt
            ]
        );


        // Login successful hone ke baad failed attempts remove
        loginAttempts.delete(ip);


        // Flutter ko successful login response bhejna
        return res.status(200).json({
            success: true,
            message: 'Login Successful',
            accessToken: token,
            refreshToken: refreshToken
        });


    } catch (e) {

        console.log('Login Error:', e.message);

        return res.status(500).json({
            success: false,
            message: 'Internal Server Error'
        });

    }

});


// ======================================
// REFRESH TOKEN API
// ======================================

app.post('/refresh', async (req, res) => {

    try {

        const { refreshToken } = req.body;

        // Check karna ki refresh token mila hai ya nahi
        if (!refreshToken) {

            return res.status(401).json({
                success: false,
                message: 'Refresh Token Required'
            });
        }


        // Refresh token verify karna
        const decode = jwt.verify(
            refreshToken,
            process.env.JWT_REFRESH_SECRET
        );


        // Token se user ID nikalna
        const user_id = decode.user_id;


        // Received refresh token ka hash banana
        const tokenHash = crypto
            .createHash('sha256')
            .update(refreshToken)
            .digest('hex');


        // Database mein valid refresh token check karna
        const result = await pool.query(
            'SELECT * FROM refresh_tokens WHERE token_hash = $1 AND revoked = false AND expires_at > NOW()',
            [tokenHash]
        );


        // Token valid hai ya nahi check karna
        if (
            result.rows.length === 0 ||
            Number(result.rows[0].user_id) !== Number(user_id)
        ) {

            return res.status(401).json({
                success: false,
                message: 'Invalid Or Expired Refresh Token'
            });
        }


        // Naya access token generate karna
        const newAccessToken = jwt.sign(
            { user_id: user_id },
            process.env.JWT_SECRET,
            { expiresIn: '15s' }
        );


        // Flutter ko naya access token bhejna
        return res.status(200).json({
            success: true,
            message: 'Access Token Generated Successfully',
            accessToken: newAccessToken
        });


    } catch (e) {

        console.log('Refresh Token Error:', e.message);

        return res.status(401).json({
            success: false,
            message: 'Invalid Or Expired Refresh Token'
        });

    }

});


// ======================================
// PROFILE API
// ======================================

app.get('/profile', authMiddleware, async (req, res) => {

    try {

        // Middleware se authenticated user ki ID milti hai
        const user_id = req.user_id;

        // Database se user ki profile fetch karna
        const result = await pool.query(
            'SELECT id, name, email, mobile FROM users WHERE id = $1',
            [user_id]
        );


        // User database mein nahi mila
        if (result.rows.length === 0) {

            return res.status(404).json({
                success: false,
                message: 'User Not Found'
            });
        }


        // User profile response bhejna
        return res.status(200).json({
            success: true,
            message: 'Profile Fetched Successfully',
            user: result.rows[0]
        });


    } catch (e) {

        console.log('Profile Error:', e.message);

        return res.status(500).json({
            success: false,
            message: 'Internal Server Error'
        });

    }

});


// ======================================
// START SERVER
// ======================================

app.listen(3000, () => {

    console.log('Server is running on port 3000');

});
