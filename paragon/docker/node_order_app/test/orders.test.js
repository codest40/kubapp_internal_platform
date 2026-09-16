const test = require("node:test");
const assert = require("node:assert");

const {
    createOrder,
    getOrderById
} = require("../src/orders");

test("createOrder creates an order", () => {
    const order = createOrder(
        "Mark",
        "Laptop",
        1
    );

    assert.strictEqual(order.customer, "Mark");
    assert.strictEqual(order.item, "Laptop");
    assert.strictEqual(order.quantity, 1);
    assert.strictEqual(order.status, "CREATED");
});

test("getOrderById returns an existing order", () => {
    const order = createOrder(
        "Jane",
        "Monitor",
        2
    );

    const foundOrder = getOrderById(order.id);

    assert.deepStrictEqual(foundOrder, order);
});

test("getOrderById returns undefined for an unknown order", () => {
    const order = getOrderById(999999);

    assert.strictEqual(order, undefined);
});
