import React, { useState } from 'react';
import { 
  View, 
  Text, 
  TextInput, 
  Button, 
  StyleSheet, 
  SafeAreaView,
  ScrollView 
} from 'react-native';

// Типы TypeScript
type Task = {
  id: number;
  text: string;
  completed: boolean;
};

const App: React.FC = () => {
  // Состояния
  const [tasks, setTasks] = useState<Task[]>([]);
  const [inputText, setInputText] = useState<string>('');
  const [counter, setCounter] = useState<number>(0);

  // Функция для добавления задачи
  const addTask = () => {
    if (inputText.trim()) {
      const newTask: Task = {
        id: Date.now(),
        text: inputText,
        completed: false
      };
      setTasks([...tasks, newTask]);
      setInputText('');
      setCounter(counter + 1);
    }
  };

  // Функция для удаления задачи
  const deleteTask = (id: number) => {
    setTasks(tasks.filter(task => task.id !== id));
  };

  // Функция для отметки выполнения задачи
  const toggleTask = (id: number) => {
    setTasks(tasks.map(task =>
      task.id === id ? { ...task, completed: !task.completed } : task
    ));
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Мои задачи</Text>
        <Text style={styles.counter}>Всего: {tasks.length}</Text>
      </View>

      <View style={styles.inputContainer}>
        <TextInput
          style={styles.input}
          placeholder="Введите задачу..."
          value={inputText}
          onChangeText={setInputText}
          onSubmitEditing={addTask}
        />
        <Button title="Добавить" onPress={addTask} />
      </View>

      <ScrollView style={styles.taskList}>
        {tasks.map(task => (
          <View key={task.id} style={styles.taskItem}>
            <Text
              style={[
                styles.taskText,
                task.completed && styles.completedTask
              ]}
              onPress={() => toggleTask(task.id)}
            >
              {task.text}
            </Text>
            <Button
              title="❌"
              onPress={() => deleteTask(task.id)}
              color="red"
            />
          </View>
        ))}
        
        {tasks.length === 0 && (
          <Text style={styles.emptyText}>Нет задач. Добавьте первую!</Text>
        )}
      </ScrollView>
    </SafeAreaView>
  );
};

// Стили
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
    padding: 16,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333',
  },
  counter: {
    fontSize: 16,
    color: '#666',
  },
  inputContainer: {
    flexDirection: 'row',
    marginBottom: 20,
  },
  input: {
    flex: 1,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    marginRight: 10,
    backgroundColor: 'white',
  },
  taskList: {
    flex: 1,
  },
  taskItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 8,
    marginBottom: 10,
    borderWidth: 1,
    borderColor: '#eee',
  },
  taskText: {
    fontSize: 16,
    flex: 1,
  },
  completedTask: {
    textDecorationLine: 'line-through',
    color: '#999',
  },
  emptyText: {
    textAlign: 'center',
    color: '#999',
    marginTop: 50,
    fontSize: 16,
  },
});

export default App;
