const orders = [];

let nextOrderId = 1;

function createOrder(customer, item, quantity) {
    const order = {
        id: nextOrderId,
        customer,
        item,
        quantity,
        status: "CREATED"
    };

    nextOrderId += 1;
    orders.push(order);

    return order;
}

function getOrders() {
    return orders;
}

function getOrderById(orderId) {
    return orders.find((order) => order.id === orderId);
}

module.exports = {
    createOrder,
    getOrders,
    getOrderById
};
