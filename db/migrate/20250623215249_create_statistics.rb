class CreateStatistics < ActiveRecord::Migration[7.2]
  def change
    create_table :statistics do |t|
      t.integer :k
      t.integer :l
      t.float :precisao
      t.integer :classes_geradas

      t.timestamps
    end
  end
end
