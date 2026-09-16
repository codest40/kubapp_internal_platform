
# URL Shortener

A simple URL Shortener application built with Node.js and Express.

It provides a small frontend UI and backend API for creating short links, redirecting users, listing saved URLs, deleting links, and checking click statistics.

This project is designed for:

Docker build and push testing
GitHub Actions CI/CD practice
Kubernetes / EKS deployment
Ingress and LoadBalancer testing
ArgoCD GitOps workflows
Features
Shorten long URLs
Redirect using short codes
View all saved URLs
Delete short URLs
Track click statistics
Run locally
Install dependencies
cd backend
npm install
Start the app
npm start

The app runs on:

http://localhost:3000
API Endpoints
POST   /api/shorten
GET    /api/urls
GET    /:code
DELETE /api/urls/:code
GET    /api/stats/:code
