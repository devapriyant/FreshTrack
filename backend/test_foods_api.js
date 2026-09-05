require("dotenv").config();
const http = require("http");
const pool = require("./config/database");

// Start server in-process on a random or test port (5055) to test against live routes
const express = require("express");
const cors = require("cors");
const authRoutes = require("./routes/auth");
const foodRoutes = require("./routes/foods");

const app = express();
app.use(cors());
app.use(express.json());

app.get("/", (req, res) => {
  res.json({ message: "FreshTrack authentication server is running" });
});

app.get("/api/database-test", async (req, res, next) => {
  try {
    const result = await pool.query("SELECT NOW() AS current_time");
    res.json({
      message: "PostgreSQL connected successfully",
      databaseTime: result.rows[0].current_time,
    });
  } catch (error) {
    next(error);
  }
});

app.use("/api/auth", authRoutes);
app.use("/api/foods", foodRoutes);

app.use((req, res) => {
  res.status(404).json({ message: `Cannot ${req.method} ${req.originalUrl}` });
});

app.use((err, req, res, next) => {
  const statusCode = err.statusCode || err.status || 500;
  res.status(statusCode).json({
    message: err.message || "An internal server error occurred.",
  });
});

const TEST_PORT = 5055;
let server;

function request(method, path, body = null, token = null) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const headers = {
      "Content-Type": "application/json",
    };
    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }
    if (data) {
      headers["Content-Length"] = Buffer.byteLength(data);
    }

    const req = http.request(
      {
        hostname: "localhost",
        port: TEST_PORT,
        path,
        method,
        headers,
      },
      (res) => {
        let responseBody = "";
        res.on("data", (chunk) => (responseBody += chunk));
        res.on("end", () => {
          try {
            const parsed = responseBody ? JSON.parse(responseBody) : {};
            resolve({ status: res.statusCode, body: parsed });
          } catch (e) {
            resolve({ status: res.statusCode, body: responseBody });
          }
        });
      }
    );

    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

async function runTests() {
  console.log("--- Starting FreshTrack Phase 2 Backend Automated Tests ---");
  const timestamp = Date.now();
  const userAEmail = `test_user_a_${timestamp}@example.com`;
  const userBEmail = `test_user_b_${timestamp}@example.com`;
  const password = "TestPassword123!";

  let userAId = null;
  let userBId = null;
  let tokenA = null;
  let tokenB = null;
  let createdFoodAId = null;

  try {
    // 1. Health check & DB test
    const health = await request("GET", "/");
    if (health.status !== 200) throw new Error(`Health check failed: ${health.status}`);
    console.log("✓ Health check endpoint works (200)");

    const dbTest = await request("GET", "/api/database-test");
    if (dbTest.status !== 200) throw new Error(`DB test failed: ${dbTest.status}`);
    console.log("✓ Database connectivity test works (200)");

const { getTestCapturedOtp } = require("./services/emailService");
    // 2. Register & Login User A
    const regA = await request("POST", "/api/auth/register", {
      name: "User A",
      email: userAEmail,
      password,
    });
    if (regA.status !== 201) throw new Error(`Register User A failed: ${JSON.stringify(regA.body)}`);
    const capturedA = getTestCapturedOtp(userAEmail);
    const verRegA = await request("POST", "/api/auth/register/verify-otp", {
      challenge_id: regA.body.challenge_id,
      otp: capturedA.otp,
    });
    if (verRegA.status !== 200) throw new Error(`Verify User A failed: ${JSON.stringify(verRegA.body)}`);

    const loginA1 = await request("POST", "/api/auth/login", {
      email: userAEmail,
      password,
    });
    const capturedLoginA = getTestCapturedOtp(userAEmail);
    const loginA2 = await request("POST", "/api/auth/login/verify-otp", {
      challenge_id: loginA1.body.challenge_id,
      otp: capturedLoginA.otp,
    });
    if (loginA2.status !== 200 || !loginA2.body.token) throw new Error(`Login User A failed`);
    tokenA = loginA2.body.token;
    userAId = loginA2.body.user.id;
    console.log("✓ User A registered, verified, and logged in");

    // 3. Register & Login User B
    const regB = await request("POST", "/api/auth/register", {
      name: "User B",
      email: userBEmail,
      password,
    });
    if (regB.status !== 201) throw new Error(`Register User B failed`);
    const capturedB = getTestCapturedOtp(userBEmail);
    await request("POST", "/api/auth/register/verify-otp", {
      challenge_id: regB.body.challenge_id,
      otp: capturedB.otp,
    });

    const loginB1 = await request("POST", "/api/auth/login", {
      email: userBEmail,
      password,
    });
    const capturedLoginB = getTestCapturedOtp(userBEmail);
    const loginB2 = await request("POST", "/api/auth/login/verify-otp", {
      challenge_id: loginB1.body.challenge_id,
      otp: capturedLoginB.otp,
    });
    if (loginB2.status !== 200 || !loginB2.body.token) throw new Error(`Login User B failed`);
    tokenB = loginB2.body.token;
    userBId = loginB2.body.user.id;
    console.log("✓ User B registered, verified, and logged in");

    // 4. Test 401 without token or invalid token
    const noToken = await request("GET", "/api/foods");
    if (noToken.status !== 401) throw new Error(`Expected 401 without token, got ${noToken.status}`);
    console.log("✓ GET /api/foods returns 401 without token");

    const invalidToken = await request("GET", "/api/foods", null, "invalid_jwt_token");
    if (invalidToken.status !== 401) throw new Error(`Expected 401 with invalid token, got ${invalidToken.status}`);
    console.log("✓ GET /api/foods returns 401 with invalid token");

    // 5. Test rejection of user_id in request bodies (hasOwnProperty check)
    const rejectUserIdPost = await request("POST", "/api/foods", {
      food_name: "Milk",
      expiry_date: "2026-09-10",
      user_id: 999,
    }, tokenA);
    if (rejectUserIdPost.status !== 400) throw new Error(`Expected 400 on user_id in body, got ${rejectUserIdPost.status}`);

    const rejectNullUserId = await request("POST", "/api/foods", {
      food_name: "Milk",
      expiry_date: "2026-09-10",
      user_id: null,
    }, tokenA);
    if (rejectNullUserId.status !== 400) throw new Error(`Expected 400 on null user_id in body, got ${rejectNullUserId.status}`);

    const rejectCamelUserId = await request("POST", "/api/foods", {
      food_name: "Milk",
      expiry_date: "2026-09-10",
      userId: 1,
    }, tokenA);
    if (rejectCamelUserId.status !== 400) throw new Error(`Expected 400 on userId in body, got ${rejectCamelUserId.status}`);
    console.log("✓ POST /api/foods rejects user_id/userId in body with 400 (including null/numeric)");

    // 6. Test input validations
    const emptyName = await request("POST", "/api/foods", {
      food_name: "   ",
      expiry_date: "2026-09-10",
    }, tokenA);
    if (emptyName.status !== 400) throw new Error(`Expected 400 on empty food_name`);

    const invalidQty = await request("POST", "/api/foods", {
      food_name: "Apple",
      expiry_date: "2026-09-10",
      quantity: 0,
    }, tokenA);
    if (invalidQty.status !== 400) throw new Error(`Expected 400 on 0 quantity`);

    const invalidDateFormat = await request("POST", "/api/foods", {
      food_name: "Apple",
      expiry_date: "2026/09/10",
    }, tokenA);
    if (invalidDateFormat.status !== 400) throw new Error(`Expected 400 on 2026/09/10 date format`);

    const impossibleDate = await request("POST", "/api/foods", {
      food_name: "Apple",
      expiry_date: "2026-02-30",
    }, tokenA);
    if (impossibleDate.status !== 400) throw new Error(`Expected 400 on 2026-02-30`);

    const purchaseAfterExpiry = await request("POST", "/api/foods", {
      food_name: "Apple",
      purchase_date: "2026-09-15",
      expiry_date: "2026-09-10",
    }, tokenA);
    if (purchaseAfterExpiry.status !== 400) throw new Error(`Expected 400 on purchase_date > expiry_date`);
    console.log("✓ Strict input validation working (empty name, bad quantity, invalid calendar date, purchase > expiry)");

    // 7. POST /api/foods - User A creates items
    const createItem1 = await request("POST", "/api/foods", {
      food_name: "Organic Milk",
      category: "Dairy",
      quantity: 2,
      purchase_date: "2026-09-01",
      expiry_date: "2026-09-08",
      storage_location: "Refrigerator",
      notes: "Full fat whole milk",
    }, tokenA);
    if (createItem1.status !== 201 || !createItem1.body.id) throw new Error(`POST /api/foods item 1 failed: ${JSON.stringify(createItem1.body)}`);
    createdFoodAId = createItem1.body.id;

    const createItem2 = await request("POST", "/api/foods", {
      food_name: "Fresh Spinach",
      category: "Produce",
      quantity: 1,
      expiry_date: "2026-09-03",
      storage_location: "Refrigerator",
    }, tokenA);
    if (createItem2.status !== 201) throw new Error(`POST /api/foods item 2 failed`);

    const createItem3 = await request("POST", "/api/foods", {
      food_name: "Cheddar Cheese",
      category: "Dairy",
      quantity: 1,
      expiry_date: "2026-09-20",
      storage_location: "Refrigerator",
    }, tokenA);
    if (createItem3.status !== 201) throw new Error(`POST /api/foods item 3 failed`);

    console.log("✓ User A successfully created 3 food items with HTTP 201");

    // 8. GET /api/foods - List and default sort
    const listAll = await request("GET", "/api/foods", null, tokenA);
    if (listAll.status !== 200 || listAll.body.count !== 3) throw new Error(`GET /api/foods count mismatch, expected 3 got ${listAll.body.count}`);
    // Check sort: nearest expiry first (Spinach 2026-09-03, Milk 2026-09-08, Cheese 2026-09-20)
    if (listAll.body.items[0].food_name !== "Fresh Spinach") throw new Error(`Sort order incorrect: first item is ${listAll.body.items[0].food_name}`);
    console.log("✓ GET /api/foods returns items sorted by expiry_date ASC, created_at DESC");

    // 9. Filters
    const searchFilter = await request("GET", "/api/foods?search=milk", null, tokenA);
    if (searchFilter.status !== 200 || searchFilter.body.count !== 1 || searchFilter.body.items[0].food_name !== "Organic Milk") {
      throw new Error(`Search filter failed`);
    }
    console.log("✓ GET /api/foods with search filter works");

    const categoryFilter = await request("GET", "/api/foods?category=Dairy", null, tokenA);
    if (categoryFilter.status !== 200 || categoryFilter.body.count !== 2) {
      throw new Error(`Category filter failed, count was ${categoryFilter.body.count}`);
    }
    console.log("✓ GET /api/foods with category filter works");

    const badStatusFilter = await request("GET", "/api/foods?status=expired", null, tokenA);
    if (badStatusFilter.status !== 400) throw new Error(`Expected 400 on status=expired, got ${badStatusFilter.status}`);
    console.log("✓ GET /api/foods rejects non-database status (e.g. status=expired) with 400");

    // 10. GET /api/foods/:id
    const getItem = await request("GET", `/api/foods/${createdFoodAId}`, null, tokenA);
    if (getItem.status !== 200 || getItem.body.food_name !== "Organic Milk") throw new Error(`GET /api/foods/:id failed`);
    console.log("✓ GET /api/foods/:id returns item for owner (200)");

    // 11. Security: User B tries to access User A's item -> 404
    const userBGet = await request("GET", `/api/foods/${createdFoodAId}`, null, tokenB);
    if (userBGet.status !== 404) throw new Error(`Expected 404 for User B accessing User A item, got ${userBGet.status}`);
    console.log("✓ User B cannot access User A item via GET /api/foods/:id (returns 404)");

    const userBList = await request("GET", "/api/foods", null, tokenB);
    if (userBList.status !== 200 || userBList.body.count !== 0) throw new Error(`User B list should be 0 items`);
    console.log("✓ User B inventory is isolated and empty (count: 0)");

    // 12. PUT /api/foods/:id - Full update
    const putRejectUserId = await request("PUT", `/api/foods/${createdFoodAId}`, {
      food_name: "Organic Whole Milk",
      quantity: 3,
      expiry_date: "2026-09-09",
      user_id: userAId,
    }, tokenA);
    if (putRejectUserId.status !== 400) throw new Error(`Expected 400 for user_id in PUT body`);

    const updateItem = await request("PUT", `/api/foods/${createdFoodAId}`, {
      food_name: "Organic Whole Milk Updated",
      category: "Dairy & Eggs",
      quantity: 3,
      purchase_date: null,
      expiry_date: "2026-09-09",
      storage_location: "Fridge Door",
      notes: null,
    }, tokenA);
    if (updateItem.status !== 200 || updateItem.body.food_name !== "Organic Whole Milk Updated" || updateItem.body.notes !== null) {
      throw new Error(`PUT /api/foods/:id failed: ${JSON.stringify(updateItem.body)}`);
    }
    console.log("✓ PUT /api/foods/:id performs full update and clears optional fields when null");

    const userBPut = await request("PUT", `/api/foods/${createdFoodAId}`, {
      food_name: "Hacked by B",
      quantity: 1,
      expiry_date: "2026-09-09",
    }, tokenB);
    if (userBPut.status !== 404) throw new Error(`Expected 404 for User B PUT, got ${userBPut.status}`);
    console.log("✓ User B cannot update User A item via PUT (returns 404)");

    // 13. PATCH /api/foods/:id/status
    const patchRejectUserId = await request("PATCH", `/api/foods/${createdFoodAId}/status`, {
      status: "consumed",
      user_id: userAId,
    }, tokenA);
    if (patchRejectUserId.status !== 400) throw new Error(`Expected 400 on user_id in PATCH body`);

    const patchInvalidStatus = await request("PATCH", `/api/foods/${createdFoodAId}/status`, {
      status: "invalid_status",
    }, tokenA);
    if (patchInvalidStatus.status !== 400) throw new Error(`Expected 400 on invalid status`);

    const patchStatus = await request("PATCH", `/api/foods/${createdFoodAId}/status`, {
      status: "consumed",
    }, tokenA);
    if (patchStatus.status !== 200 || patchStatus.body.status !== "consumed") {
      throw new Error(`PATCH /api/foods/:id/status failed`);
    }
    console.log("✓ PATCH /api/foods/:id/status successfully transitions status to 'consumed'");

    const userBPatch = await request("PATCH", `/api/foods/${createdFoodAId}/status`, {
      status: "discarded",
    }, tokenB);
    if (userBPatch.status !== 404) throw new Error(`Expected 404 for User B PATCH, got ${userBPatch.status}`);
    console.log("✓ User B cannot update status of User A item (returns 404)");

    // 14. DELETE /api/foods/:id
    const userBDelete = await request("DELETE", `/api/foods/${createdFoodAId}`, null, tokenB);
    if (userBDelete.status !== 404) throw new Error(`Expected 404 for User B DELETE, got ${userBDelete.status}`);
    console.log("✓ User B cannot delete User A item (returns 404)");

    const deleteItem = await request("DELETE", `/api/foods/${createdFoodAId}`, null, tokenA);
    if (deleteItem.status !== 200 || deleteItem.body.message !== "Food item deleted successfully.") {
      throw new Error(`DELETE /api/foods/:id failed`);
    }
    console.log("✓ DELETE /api/foods/:id successfully deletes item for owner (200)");

    const getDeleted = await request("GET", `/api/foods/${createdFoodAId}`, null, tokenA);
    if (getDeleted.status !== 404) throw new Error(`Expected 404 after deletion, got ${getDeleted.status}`);
    console.log("✓ Deleted item returns 404 on subsequent GET");

    console.log("\nALL BACKEND INTEGRATION TESTS PASSED SUCCESSFULLY! 🎉");
  } finally {
    // Teardown test users and cascade-delete food items
    if (userAId || userBId) {
      await pool.query("DELETE FROM users WHERE id IN ($1, $2)", [userAId || -1, userBId || -1]);
      console.log("✓ Cleaned up test user accounts and their associated records.");
    }
  }
}

server = app.listen(TEST_PORT, async () => {
  try {
    await runTests();
    server.close();
    await pool.end();
    process.exit(0);
  } catch (err) {
    console.error("❌ TEST FAILURE:", err.message);
    server.close();
    await pool.end();
    process.exit(1);
  }
});
