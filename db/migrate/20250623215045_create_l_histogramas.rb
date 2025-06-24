class CreateLHistogramas < ActiveRecord::Migration[7.2]
  def change
    create_table :l_histogramas do |t|
      t.integer :data_1
      t.integer :data_2
      t.integer :data_3
      t.integer :data_4
      t.integer :data_5

      t.timestamps
    end
  end
end
