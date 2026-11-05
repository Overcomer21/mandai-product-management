import {Kafka} from 'kafkajs';
// Independent adapter. Only publish from a durable SQL outbox dispatcher.
export class KafkaEventPublisher{
 constructor(brokers){this.kafka=new Kafka({clientId:'mandai-node-api',brokers});this.producer=this.kafka.producer();this.connected=false;}
 async publishOutboxEvent(event){if(!this.connected){await this.producer.connect();this.connected=true;}await this.producer.send({topic:'mandai.orders.v1',messages:[{key:String(event.aggregateId),value:JSON.stringify({id:event.id,type:event.type,payload:event.payload})}]});}
 async close(){if(this.connected)await this.producer.disconnect();}
}
