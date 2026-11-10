import { createBrowserRouter } from 'react-router-dom';
import HomePage from './pages/HomePage';
import LoginPage from './pages/login/login';
import Dashboard from './layouts/Dashboard';
import NonAuth from './layouts/NonAuth';
import Root from './layouts/Root';
import Users from './pages/users/Users';
import Tenants from './pages/tenants/Tenants';
import Products from './pages/products/Products';
import Orders from './pages/orders/Orders';
import SingleOrder from './pages/orders/SingleOrder';

const basename = import.meta.env.BASE_URL === '/' ? undefined : import.meta.env.BASE_URL.replace(/\/$/, '');

export const router = createBrowserRouter([
    {
        path: '/',
        element: <Root />,
        children: [
            {
                path: '',
                element: <Dashboard />,
                children: [
                    {
                        path: '',
                        element: <HomePage />,
                    },
                    {
                        path: '/users',
                        element: <Users />,
                    },
                    {
                        path: '/restaurants',
                        element: <Tenants />,
                    },
                    {
                        path: '/products',
                        element: <Products />,
                    },
                    {
                        path: '/orders',
                        element: <Orders />,
                    },
                    {
                        path: '/orders/:orderId',
                        element: <SingleOrder />,
                    },
                ],
            },
            {
                path: '/auth',
                element: <NonAuth />,
                children: [
                    {
                        path: 'login',
                        element: <LoginPage />,
                    },
                ],
            },
        ],
    },
], { basename });
