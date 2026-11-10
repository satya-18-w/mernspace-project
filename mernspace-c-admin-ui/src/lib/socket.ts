import { io } from 'socket.io-client';

const socket = io(import.meta.env.VITE_SOCKET_SERVICE_URL);

socket.on('connect', () => {
    console.log(`Connected socket: `, socket.id);
});

socket.on('disconnect', () => {
    console.log('Disconnected: ', socket.id);
});

export default socket;
