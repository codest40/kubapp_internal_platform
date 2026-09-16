const express = require("express");

const {
    createOrder,
    getOrders,
    getOrderById
} = require("./orders");

const app = express();

app.use(express.json());

app.get("/health", (request, response) => {
    response.status(200).json({
        status: "ok"
    });
});

app.get("/orders", (request, response) => {
    response.status(200).json(getOrders());
});

app.get("/orders/:id", (request, response) => {
    const orderId = Number(request.params.id);

    const order = getOrderById(orderId);

    if (!order) {
        response.status(404).json({
            error: "Order not found"
        });

        return;
    }

    response.status(200).json(order);
});

app.post("/orders", (request, response) => {
    const {
        customer,
        item,
        quantity
    } = request.body;

    if (!customer || !item || !Number.isInteger(quantity) || quantity < 1) {
        response.status(400).json({
            error: "Invalid order data"
        });

        return;
    }

    const order = createOrder(
        customer,
        item,
        quantity
    );

    response.status(201).json(order);
});

module.exports = app;
