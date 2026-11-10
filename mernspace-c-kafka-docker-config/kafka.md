### Create Kafka topic:

./kafka-topics.sh --create --topic product --bootstrap-server localhost:9092

List Kafka topics:

./kafka-topics.sh --list --bootstrap-server localhost:9092

Get Topic details, partition counts etc.
./kafka-topics.sh --describe --bootstrap-server localhost:9092 --topic product

Alter the topic, change partition:
./kafka-topics.sh --alter --bootstrap-server localhost:9092 --topic product --partitions 6

Publish a message to Kafka topic

./kafka-console-producer.sh --bootstrap-server localhost:9092 --topic pricing

Check messages in a topic
./kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic product --from-beginning
