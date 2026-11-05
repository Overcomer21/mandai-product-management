import {query} from './db.js';
export class SqlIdentityRepository {
 async byEmail(email){return (await query('SELECT Id AS id, Email AS email, PasswordHash AS password_hash, Role AS role, DeliveryAddress AS delivery_address, PhoneNumber AS phone_number, PaymentMethod AS payment_method FROM Users WHERE Email=@p0',[email])).recordset[0]||null;}
 async byId(id){return (await query('SELECT Id AS id, Email AS email, PasswordHash AS password_hash, Role AS role, DeliveryAddress AS delivery_address, PhoneNumber AS phone_number, PaymentMethod AS payment_method FROM Users WHERE Id=@p0',[id])).recordset[0]||null;}
}
