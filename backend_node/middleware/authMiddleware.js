const jwt = require('jsonwebtoken');

const authMidleware = (req, res, next) => {

    const authHeader = req.headers.authorization;

    const token = authHeader && authHeader.split(' ')[1] // authHeader mein "Bearer TOKEN" hota hai.
    // split(' ') string ko space ke basis par todta hai.
    // [1] se actual JWT token milta hai, "Bearer" nahi.

    if (!token) {
        return res.status(401).json({
            success: false,
            message: 'Access Denied,Token Missing'
        })
    }

    // const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // jwt.verify() token ko verify karta hai.
    // process.env.JWT_SECRET wahi secret key hai jisse token sign hua tha.
    // decoded mein verified token ka payload milega, jaise userId.


    let decoded;

    try {
        decoded = jwt.verify(token, process.env.JWT_SECRET)
    } catch (err) {
        return res.status(401).json({
            success: false,
            message: 'Invalid Or Expired Token'
        })
    }

    req.user_id = decoded.user_id;
    // Verified JWT payload se userId nikalte hain.
    // req.userId mein ID store hoti hai.
    // Ab next API route is ID ko access kar sakta hai.

    next();
    // Token successfully verify ho gaya.
    // next() request ko aage protected API route tak bhejta hai.


    // Isse hum authMiddleware ko server.js mein import kar sakenge.
}
module.exports = authMidleware;